package core

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// WhoIsResolver cryptographically resolves a remote peer's node ID (e.g. via Tailscale WhoIs)
type WhoIsResolver func(ctx context.Context, remoteAddr string) (string, error)

// BatchSession tracks an approved active batch on receiver
type BatchSession struct {
	Manifest         *BatchManifest
	FilesRemaining   map[string]BatchFileItem
	TotalBytes       int64
	TransferredBytes int64
	FileIndex        int
	CompletedFiles   int
	CreatedAt        time.Time
}

// BatchSendSource represents a file item to be sent in a batch
type BatchSendSource struct {
	FileID   string
	FileName string
	FileSize int64
	SHA256   string
	FilePath string
	Reader   io.Reader
}

// TransferManager coordinates incoming and outgoing transfers
type TransferManager struct {
	config     *EngineConfig
	trustStore    *TrustStore
	whoIsResolver WhoIsResolver
	mu            sync.RWMutex
	pending       map[string]*TransferRequest
	batches       map[string]*BatchSession
	approvals     map[string]chan int
	cancels       map[string]context.CancelFunc
	activeCnt     int
}

func (tm *TransferManager) SetWhoIsResolver(fn WhoIsResolver) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	tm.whoIsResolver = fn
}

func NewTransferManager(cfg *EngineConfig, ts ...*TrustStore) *TransferManager {
	var store *TrustStore
	if len(ts) > 0 {
		store = ts[0]
	}
	return &TransferManager{
		config:     cfg,
		trustStore: store,
		pending:    make(map[string]*TransferRequest),
		batches:    make(map[string]*BatchSession),
		approvals:  make(map[string]chan int),
		cancels:    make(map[string]context.CancelFunc),
	}
}

func (tm *TransferManager) ResolveApproval(transferID string, decision int) bool {
	tm.mu.Lock()
	ch, ok := tm.approvals[transferID]
	delete(tm.approvals, transferID)
	tm.mu.Unlock()

	if ok && ch != nil {
		select {
		case ch <- decision:
			return true
		default:
		}
	}
	return false
}

func (tm *TransferManager) RegisterCancel(transferID string, cancel context.CancelFunc) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	tm.cancels[transferID] = cancel
}

func (tm *TransferManager) UnregisterCancel(transferID string) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	delete(tm.cancels, transferID)
}

func (tm *TransferManager) Cancel(transferID string) bool {
	tm.mu.Lock()
	cancel, ok := tm.cancels[transferID]
	delete(tm.cancels, transferID)
	tm.mu.Unlock()

	if ok && cancel != nil {
		cancel()
		return true
	}
	return false
}

// Router returns http.Handler for transfer protocol endpoints
func (tm *TransferManager) Router(nodeID string) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /v1/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(NodeInfo{
			NodeID:          nodeID,
			DeviceName:      tm.config.DeviceName,
			OS:              runtime.GOOS,
			ProtocolVersion: ProtocolVersion,
		})
	})

	mux.HandleFunc("POST /v1/transfer/request", func(w http.ResponseWriter, r *http.Request) {
		transferID := r.Header.Get(HeaderTransferID)
		fileName := sanitizeFileName(r.Header.Get(HeaderFileName))
		sizeStr := r.Header.Get(HeaderFileSize)
		fileHash := r.Header.Get(HeaderFileSHA256)
		senderName := r.Header.Get(HeaderSenderName)

		tm.mu.RLock()
		resolver := tm.whoIsResolver
		tm.mu.RUnlock()

		senderNodeID := ""
		if resolver != nil {
			if verified, err := resolver(r.Context(), r.RemoteAddr); err == nil && verified != "" {
				senderNodeID = verified
			} else {
				senderNodeID = r.RemoteAddr
			}
		} else {
			senderNodeID = r.Header.Get(HeaderSenderNodeID)
			if senderNodeID == "" {
				senderNodeID = r.RemoteAddr
			}
		}

		if transferID == "" || fileName == "" || sizeStr == "" || fileHash == "" {
			http.Error(w, "missing required transfer headers", http.StatusBadRequest)
			return
		}

		sizeBytes, err := strconv.ParseInt(sizeStr, 10, 64)
		if err != nil || sizeBytes < 0 {
			http.Error(w, "invalid file size", http.StatusBadRequest)
			return
		}

		// Storage pre-flight check
		if !checkDiskSpaceAvailable(tm.config.DownloadDir, sizeBytes+50*1024*1024) {
			http.Error(w, "insufficient disk space on receiver", http.StatusInsufficientStorage)
			return
		}

		tm.mu.Lock()
		if _, exists := tm.pending[transferID]; exists {
			tm.mu.Unlock()
			http.Error(w, "transfer id conflict", http.StatusConflict)
			return
		}
		tm.mu.Unlock()

		// Approval check
		trusted := tm.trustStore != nil && tm.trustStore.IsTrusted(senderNodeID)
		needsApproval := tm.config.RequireApproval && !(trusted && tm.config.AutoAcceptTrusted)

		if needsApproval {
			tm.mu.Lock()
			if len(tm.approvals) >= 3 {
				tm.mu.Unlock()
				http.Error(w, "too many pending approval requests", http.StatusTooManyRequests)
				return
			}
			respCh := make(chan int, 1)
			tm.approvals[transferID] = respCh
			tm.mu.Unlock()

			if tm.config.OnIncomingApproval != nil {
				tm.config.OnIncomingApproval(transferID, senderNodeID, senderName, filepath.Base(fileName), sizeBytes)
			} else if tm.config.OnIncomingRequest != nil {
				go func() {
					acc := tm.config.OnIncomingRequest(transferID, senderName, filepath.Base(fileName), sizeBytes)
					if acc {
						tm.ResolveApproval(transferID, ApprovalDecisionAccept)
					} else {
						tm.ResolveApproval(transferID, ApprovalDecisionDecline)
					}
				}()
			}

			select {
			case dec := <-respCh:
				if dec == ApprovalDecisionAlwaysTrust {
					if tm.trustStore != nil {
						_ = tm.trustStore.AddTrusted(senderNodeID, senderName)
					}
				} else if dec != ApprovalDecisionAccept {
					http.Error(w, "transfer rejected by user", http.StatusForbidden)
					return
				}
			case <-time.After(60 * time.Second):
				tm.mu.Lock()
				delete(tm.approvals, transferID)
				tm.mu.Unlock()
				http.Error(w, "transfer approval timed out", http.StatusRequestTimeout)
				return
			case <-r.Context().Done():
				tm.mu.Lock()
				delete(tm.approvals, transferID)
				tm.mu.Unlock()
				return
			}
		} else if tm.config.OnIncomingRequest != nil {
			if !tm.config.OnIncomingRequest(transferID, senderName, filepath.Base(fileName), sizeBytes) {
				http.Error(w, "transfer rejected", http.StatusForbidden)
				return
			}
		}

		req := &TransferRequest{
			TransferID: transferID,
			FileName:   filepath.Base(fileName),
			FileSize:   sizeBytes,
			SHA256:     fileHash,
			SenderName: senderName,
			CreatedAt:  time.Now(),
		}

		tm.mu.Lock()
		tm.pending[transferID] = req
		tm.mu.Unlock()

		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("POST /v1/transfer/batch/request", func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1MB max for manifest JSON
		var manifest BatchManifest
		if err := json.NewDecoder(r.Body).Decode(&manifest); err != nil {
			http.Error(w, "invalid batch manifest JSON", http.StatusBadRequest)
			return
		}

		if manifest.BatchID == "" || len(manifest.Files) == 0 || manifest.TotalBytes <= 0 {
			http.Error(w, "invalid batch parameters", http.StatusBadRequest)
			return
		}

		var calculatedTotal int64
		for i, f := range manifest.Files {
			cleanName := sanitizeFileName(f.FileName)
			if f.FileID == "" || cleanName == "" || f.FileSize < 0 || f.SHA256 == "" {
				http.Error(w, "invalid file entry in batch", http.StatusBadRequest)
				return
			}
			manifest.Files[i].FileName = cleanName
			calculatedTotal += f.FileSize
		}

		if calculatedTotal != manifest.TotalBytes {
			http.Error(w, "batch total size mismatch", http.StatusBadRequest)
			return
		}

		// Storage pre-flight check: totalBytes + 50MB
		if !checkDiskSpaceAvailable(tm.config.DownloadDir, manifest.TotalBytes+50*1024*1024) {
			http.Error(w, "insufficient disk space on receiver", http.StatusInsufficientStorage)
			return
		}

		tm.mu.RLock()
		resolver := tm.whoIsResolver
		tm.mu.RUnlock()

		senderNodeID := ""
		if resolver != nil {
			if verified, err := resolver(r.Context(), r.RemoteAddr); err == nil && verified != "" {
				senderNodeID = verified
			} else {
				senderNodeID = r.RemoteAddr
			}
		} else {
			senderNodeID = manifest.SenderNodeID
			if senderNodeID == "" {
				senderNodeID = r.RemoteAddr
			}
		}
		senderName := manifest.SenderName
		if senderName == "" {
			senderName = "Peer"
		}

		tm.mu.Lock()
		if _, exists := tm.batches[manifest.BatchID]; exists {
			tm.mu.Unlock()
			http.Error(w, "batch id conflict", http.StatusConflict)
			return
		}
		tm.mu.Unlock()

		// Approval check
		trusted := tm.trustStore != nil && tm.trustStore.IsTrusted(senderNodeID)
		needsApproval := tm.config.RequireApproval && !(trusted && tm.config.AutoAcceptTrusted)

		fileSummary := fmt.Sprintf("%d files", len(manifest.Files))
		if len(manifest.Files) == 1 {
			fileSummary = manifest.Files[0].FileName
		} else if len(manifest.Files) <= 2 {
			fileSummary = fmt.Sprintf("%d files: %s, %s", len(manifest.Files), manifest.Files[0].FileName, manifest.Files[1].FileName)
		} else {
			fileSummary = fmt.Sprintf("%d files: %s...", len(manifest.Files), manifest.Files[0].FileName)
		}

		if needsApproval {
			tm.mu.Lock()
			if len(tm.approvals) >= 3 {
				tm.mu.Unlock()
				http.Error(w, "too many pending approval requests", http.StatusTooManyRequests)
				return
			}
			respCh := make(chan int, 1)
			tm.approvals[manifest.BatchID] = respCh
			tm.mu.Unlock()

			if tm.config.OnIncomingApproval != nil {
				tm.config.OnIncomingApproval(manifest.BatchID, senderNodeID, senderName, fileSummary, manifest.TotalBytes)
			} else if tm.config.OnIncomingRequest != nil {
				go func() {
					acc := tm.config.OnIncomingRequest(manifest.BatchID, senderName, fileSummary, manifest.TotalBytes)
					if acc {
						tm.ResolveApproval(manifest.BatchID, ApprovalDecisionAccept)
					} else {
						tm.ResolveApproval(manifest.BatchID, ApprovalDecisionDecline)
					}
				}()
			}

			select {
			case dec := <-respCh:
				if dec == ApprovalDecisionAlwaysTrust {
					if tm.trustStore != nil {
						_ = tm.trustStore.AddTrusted(senderNodeID, senderName)
					}
				} else if dec != ApprovalDecisionAccept {
					http.Error(w, "transfer rejected by user", http.StatusForbidden)
					return
				}
			case <-time.After(60 * time.Second):
				tm.mu.Lock()
				delete(tm.approvals, manifest.BatchID)
				tm.mu.Unlock()
				http.Error(w, "transfer approval timed out", http.StatusRequestTimeout)
				return
			case <-r.Context().Done():
				tm.mu.Lock()
				delete(tm.approvals, manifest.BatchID)
				tm.mu.Unlock()
				return
			}
		} else if tm.config.OnIncomingRequest != nil {
			if !tm.config.OnIncomingRequest(manifest.BatchID, senderName, fileSummary, manifest.TotalBytes) {
				http.Error(w, "transfer rejected", http.StatusForbidden)
				return
			}
		}

		filesMap := make(map[string]BatchFileItem, len(manifest.Files))
		for _, f := range manifest.Files {
			filesMap[f.FileID] = f
		}

		session := &BatchSession{
			Manifest:       &manifest,
			FilesRemaining: filesMap,
			TotalBytes:     manifest.TotalBytes,
			CreatedAt:      time.Now(),
		}

		tm.mu.Lock()
		tm.batches[manifest.BatchID] = session
		tm.mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"batchId": manifest.BatchID,
			"status":  "approved",
		})
	})

	mux.HandleFunc("POST /v1/transfer/stream", func(w http.ResponseWriter, r *http.Request) {
		batchID := r.Header.Get(HeaderBatchID)
		if batchID != "" {
			fileID := r.Header.Get(HeaderFileID)
			if fileID == "" {
				fileID = r.Header.Get(HeaderTransferID)
			}
			if fileID == "" {
				http.Error(w, "missing file ID for batch stream", http.StatusBadRequest)
				return
			}

			tm.mu.Lock()
			batch, ok := tm.batches[batchID]
			if !ok {
				tm.mu.Unlock()
				http.Error(w, "batch not found or expired", http.StatusNotFound)
				return
			}
			fileItem, fileOk := batch.FilesRemaining[fileID]
			if !fileOk {
				tm.mu.Unlock()
				http.Error(w, "file not found in batch or already transferred", http.StatusNotFound)
				return
			}
			batchFileIndex := batch.FileIndex + 1
			totalBatchFiles := len(batch.Manifest.Files)
			batchTotalBytes := batch.TotalBytes
			batchTransferredBase := batch.TransferredBytes
			tm.mu.Unlock()

			ctx, cancel := context.WithCancel(r.Context())
			defer cancel()
			tm.RegisterCancel(batchID, cancel)
			tm.RegisterCancel(fileID, cancel)
			defer func() {
				tm.UnregisterCancel(batchID)
				tm.UnregisterCancel(fileID)
			}()

			if err := os.MkdirAll(tm.config.DownloadDir, 0755); err != nil {
				msg := fmt.Sprintf("cannot create download dir: %v", err)
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(batchID, false, msg)
				}
				http.Error(w, msg, http.StatusInternalServerError)
				return
			}

			tempPath := filepath.Join(tm.config.DownloadDir, fmt.Sprintf(".%s-%s.part", batchID, fileID))
			tempFile, err := os.OpenFile(tempPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
			if err != nil {
				msg := fmt.Sprintf("cannot create temporary file: %v", err)
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(batchID, false, msg)
				}
				http.Error(w, msg, http.StatusInternalServerError)
				return
			}

			cleanupPart := func() {
				_ = tempFile.Close()
				_ = os.Remove(tempPath)
			}
			defer cleanupPart()

			hasher := sha256.New()
			buf := make([]byte, BufferSize)
			var transferred int64

			for {
				select {
				case <-ctx.Done():
					cleanupPart()
					if tm.config.OnTransferComplete != nil {
						tm.config.OnTransferComplete(batchID, false, "transfer canceled")
					}
					http.Error(w, "transfer canceled", http.StatusRequestTimeout)
					return
				default:
				}

				n, readErr := r.Body.Read(buf)
				if n > 0 {
					if _, writeErr := tempFile.Write(buf[:n]); writeErr != nil {
						cleanupPart()
						msg := fmt.Sprintf("failed writing stream: %v", writeErr)
						if tm.config.OnTransferComplete != nil {
							tm.config.OnTransferComplete(batchID, false, msg)
						}
						http.Error(w, msg, http.StatusInternalServerError)
						return
					}
					hasher.Write(buf[:n])
					transferred += int64(n)

					currentBatchBytes := batchTransferredBase + transferred
					if tm.config.OnBatchProgress != nil {
						tm.config.OnBatchProgress(
							batchID,
							batchFileIndex,
							totalBatchFiles,
							fileItem.FileName,
							transferred,
							fileItem.FileSize,
							currentBatchBytes,
							batchTotalBytes,
						)
					}
					if tm.config.OnProgress != nil {
						tm.config.OnProgress(batchID, currentBatchBytes, batchTotalBytes)
					}
				}

				if readErr != nil {
					if errors.Is(readErr, io.EOF) {
						break
					}
					cleanupPart()
					msg := fmt.Sprintf("failed reading stream: %v", readErr)
					if tm.config.OnTransferComplete != nil {
						tm.config.OnTransferComplete(batchID, false, msg)
					}
					http.Error(w, msg, http.StatusBadRequest)
					return
				}
			}

			_ = tempFile.Close()

			calcHash := hex.EncodeToString(hasher.Sum(nil))
			if subtle.ConstantTimeCompare([]byte(calcHash), []byte(fileItem.SHA256)) != 1 {
				cleanupPart()
				msg := fmt.Sprintf("hash mismatch: expected %s, got %s", fileItem.SHA256, calcHash)
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(batchID, false, msg)
				}
				http.Error(w, msg, http.StatusBadRequest)
				return
			}

			destPath := resolveUniquePath(tm.config.DownloadDir, fileItem.FileName)
			if err := os.Rename(tempPath, destPath); err != nil {
				msg := fmt.Sprintf("failed moving file to destination: %v", err)
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(batchID, false, msg)
				}
				http.Error(w, msg, http.StatusInternalServerError)
				return
			}

			if tm.config.OnBatchFileReceived != nil {
				tm.config.OnBatchFileReceived(batchID, batchFileIndex, totalBatchFiles, fileItem.FileName, destPath)
			}

			tm.mu.Lock()
			delete(batch.FilesRemaining, fileID)
			batch.TransferredBytes += fileItem.FileSize
			batch.FileIndex++
			batch.CompletedFiles++
			isAllDone := len(batch.FilesRemaining) == 0
			if isAllDone {
				delete(tm.batches, batchID)
			}
			tm.mu.Unlock()

			if isAllDone {
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(batchID, true, destPath)
				}
			}

			w.WriteHeader(http.StatusOK)
			return
		}

		transferID := r.Header.Get(HeaderTransferID)
		if transferID == "" {
			http.Error(w, "missing transfer ID", http.StatusBadRequest)
			return
		}

		tm.mu.Lock()
		req, ok := tm.pending[transferID]
		if !ok {
			tm.mu.Unlock()
			http.Error(w, "transfer request not found or expired", http.StatusNotFound)
			return
		}
		delete(tm.pending, transferID)
		tm.mu.Unlock()

		ctx, cancel := context.WithCancel(r.Context())
		defer cancel()
		tm.RegisterCancel(transferID, cancel)
		defer tm.UnregisterCancel(transferID)

		if err := os.MkdirAll(tm.config.DownloadDir, 0755); err != nil {
			msg := fmt.Sprintf("cannot create download dir: %v", err)
			if tm.config.OnTransferComplete != nil {
				tm.config.OnTransferComplete(transferID, false, msg)
			}
			http.Error(w, msg, http.StatusInternalServerError)
			return
		}

		tempPath := filepath.Join(tm.config.DownloadDir, fmt.Sprintf(".%s.part", transferID))
		tempFile, err := os.OpenFile(tempPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
		if err != nil {
			msg := fmt.Sprintf("cannot create temporary file: %v", err)
			if tm.config.OnTransferComplete != nil {
				tm.config.OnTransferComplete(transferID, false, msg)
			}
			http.Error(w, msg, http.StatusInternalServerError)
			return
		}

		cleanupPart := func() {
			_ = tempFile.Close()
			_ = os.Remove(tempPath)
		}
		defer cleanupPart()

		hasher := sha256.New()
		buf := make([]byte, BufferSize)
		var transferred int64

		for {
			select {
			case <-ctx.Done():
				cleanupPart()
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(transferID, false, "transfer canceled")
				}
				http.Error(w, "transfer canceled", http.StatusRequestTimeout)
				return
			default:
			}

			n, readErr := r.Body.Read(buf)
			if n > 0 {
				if _, writeErr := tempFile.Write(buf[:n]); writeErr != nil {
					cleanupPart()
					msg := fmt.Sprintf("failed writing stream: %v", writeErr)
					if tm.config.OnTransferComplete != nil {
						tm.config.OnTransferComplete(transferID, false, msg)
					}
					http.Error(w, msg, http.StatusInternalServerError)
					return
				}
				hasher.Write(buf[:n])
				transferred += int64(n)
				if tm.config.OnProgress != nil {
					tm.config.OnProgress(transferID, transferred, req.FileSize)
				}
			}

			if readErr != nil {
				if errors.Is(readErr, io.EOF) {
					break
				}
				cleanupPart()
				msg := fmt.Sprintf("failed reading stream: %v", readErr)
				if tm.config.OnTransferComplete != nil {
					tm.config.OnTransferComplete(transferID, false, msg)
				}
				http.Error(w, msg, http.StatusBadRequest)
				return
			}
		}

		_ = tempFile.Close()

		calcHash := hex.EncodeToString(hasher.Sum(nil))
		if subtle.ConstantTimeCompare([]byte(calcHash), []byte(req.SHA256)) != 1 {
			cleanupPart()
			msg := fmt.Sprintf("hash mismatch: expected %s, got %s", req.SHA256, calcHash)
			if tm.config.OnTransferComplete != nil {
				tm.config.OnTransferComplete(transferID, false, msg)
			}
			http.Error(w, msg, http.StatusBadRequest)
			return
		}

		destPath := resolveUniquePath(tm.config.DownloadDir, req.FileName)
		if err := os.Rename(tempPath, destPath); err != nil {
			msg := fmt.Sprintf("failed moving file to destination: %v", err)
			if tm.config.OnTransferComplete != nil {
				tm.config.OnTransferComplete(transferID, false, msg)
			}
			http.Error(w, msg, http.StatusInternalServerError)
			return
		}

		if tm.config.OnTransferComplete != nil {
			tm.config.OnTransferComplete(transferID, true, destPath)
		}
		w.WriteHeader(http.StatusOK)
	})

	return mux
}

// SendStream streams payload to target peer over HTTP
func (tm *TransferManager) SendStream(
	ctx context.Context,
	client *http.Client,
	peerIP string,
	port int,
	reader io.Reader,
	fileName string,
	fileSize int64,
	sha256Hex string,
	transferID string,
	senderNodeID ...string,
) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	tm.RegisterCancel(transferID, cancel)
	defer tm.UnregisterCancel(transferID)

	targetBase := fmt.Sprintf("http://%s:%d", peerIP, port)

	// Step 1: Request permission
	reqURL := fmt.Sprintf("%s/v1/transfer/request", targetBase)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, nil)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}
	req.Header.Set(HeaderTransferID, transferID)
	req.Header.Set(HeaderFileName, fileName)
	req.Header.Set(HeaderFileSize, strconv.FormatInt(fileSize, 10))
	req.Header.Set(HeaderFileSHA256, sha256Hex)
	req.Header.Set(HeaderSenderName, tm.config.DeviceName)
	if len(senderNodeID) > 0 && senderNodeID[0] != "" {
		req.Header.Set(HeaderSenderNodeID, senderNodeID[0])
	}

	resp, err := client.Do(req)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}
	_ = resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("peer rejected transfer: HTTP %d", resp.StatusCode)
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}

	// Step 2: Stream content
	streamURL := fmt.Sprintf("%s/v1/transfer/stream", targetBase)
	pw := &progressReader{
		reader:     reader,
		total:      fileSize,
		transferID: transferID,
		onProgress: tm.config.OnProgress,
	}

	streamReq, err := http.NewRequestWithContext(ctx, http.MethodPost, streamURL, pw)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}
	streamReq.Header.Set(HeaderTransferID, transferID)
	streamReq.Header.Set("Content-Type", "application/octet-stream")
	streamReq.ContentLength = fileSize

	streamResp, err := client.Do(streamReq)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}
	defer streamResp.Body.Close()

	if streamResp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(streamResp.Body)
		err := fmt.Errorf("stream failed: HTTP %d (%s)", streamResp.StatusCode, string(bodyBytes))
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}

	tm.notifyComplete(transferID, true, "")
	return nil
}

// SendFile streams a local filesystem file
func (tm *TransferManager) SendFile(
	ctx context.Context,
	client *http.Client,
	peerIP string,
	port int,
	filePath string,
	transferID string,
	senderNodeID ...string,
) error {
	fi, err := os.Stat(filePath)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}

	f, err := os.Open(filePath)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}
	defer f.Close()

	hashHex, err := computeFileSHA256(filePath)
	if err != nil {
		tm.notifyComplete(transferID, false, err.Error())
		return err
	}

	return tm.SendStream(
		ctx,
		client,
		peerIP,
		port,
		f,
		filepath.Base(filePath),
		fi.Size(),
		hashHex,
		transferID,
		senderNodeID...,
	)
}

func (tm *TransferManager) notifyComplete(transferID string, success bool, errorMsg string) {
	if tm.config.OnTransferComplete != nil {
		tm.config.OnTransferComplete(transferID, success, errorMsg)
	}
}

func computeFileSHA256(filePath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	buf := make([]byte, BufferSize)
	if _, err := io.CopyBuffer(h, f, buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func sanitizeFileName(name string) string {
	// Strip null bytes and non-printable control characters (CWE-626, CWE-138)
	name = strings.Map(func(r rune) rune {
		if r == 0 || r < 32 || r == 127 {
			return -1
		}
		return r
	}, name)

	clean := filepath.Base(filepath.Clean(name))
	clean = strings.ReplaceAll(clean, "/", "_")
	clean = strings.ReplaceAll(clean, "\\", "_")
	clean = strings.TrimSpace(clean)
	if clean == "" || clean == "." || clean == ".." {
		return "file"
	}
	return clean
}

func resolveUniquePath(dir, filename string) string {
	cleanName := sanitizeFileName(filename)
	candidate := filepath.Join(dir, cleanName)

	// Ensure candidate path is strictly within dir (defense-in-depth against path traversal)
	rel, err := filepath.Rel(dir, candidate)
	if err != nil || strings.HasPrefix(rel, "..") || rel == "." {
		cleanName = "download"
		candidate = filepath.Join(dir, cleanName)
	}

	if _, err := os.Stat(candidate); err != nil {
		return candidate
	}

	ext := filepath.Ext(cleanName)
	base := cleanName[:len(cleanName)-len(ext)]
	counter := 1
	for counter <= 10000 {
		candidate = filepath.Join(dir, fmt.Sprintf("%s (%d)%s", base, counter, ext))
		if _, err := os.Stat(candidate); err != nil {
			return candidate
		}
		counter++
	}
	return filepath.Join(dir, fmt.Sprintf("%s-%d%s", base, time.Now().UnixNano(), ext))
}

type progressReader struct {
	reader     io.Reader
	total      int64
	current    int64
	transferID string
	onProgress func(string, int64, int64)
}

func (pr *progressReader) Read(p []byte) (int, error) {
	n, err := pr.reader.Read(p)
	if n > 0 {
		pr.current += int64(n)
		if pr.onProgress != nil {
			pr.onProgress(pr.transferID, pr.current, pr.total)
		}
	}
	return n, err
}

// SendBatch streams multiple files to target peer sequentially under a batch session
func (tm *TransferManager) SendBatch(
	ctx context.Context,
	client *http.Client,
	peerIP string,
	port int,
	batchID string,
	sources []BatchSendSource,
	senderNodeID ...string,
) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	tm.RegisterCancel(batchID, cancel)
	defer tm.UnregisterCancel(batchID)

	if len(sources) == 0 {
		err := errors.New("cannot send empty batch")
		tm.notifyComplete(batchID, false, err.Error())
		return err
	}

	var totalBytes int64
	var manifestFiles []BatchFileItem

	for i := range sources {
		src := &sources[i]
		if src.FileID == "" {
			src.FileID = fmt.Sprintf("f-%d", i+1)
		}
		if src.SHA256 == "" && src.FilePath != "" {
			h, err := computeFileSHA256(src.FilePath)
			if err != nil {
				tm.notifyComplete(batchID, false, fmt.Sprintf("failed hashing %s: %v", src.FileName, err))
				return err
			}
			src.SHA256 = h
		}
		totalBytes += src.FileSize
		manifestFiles = append(manifestFiles, BatchFileItem{
			FileID:   src.FileID,
			FileName: src.FileName,
			FileSize: src.FileSize,
			SHA256:   src.SHA256,
		})
	}

	nodeID := ""
	if len(senderNodeID) > 0 {
		nodeID = senderNodeID[0]
	}

	manifest := BatchManifest{
		BatchID:      batchID,
		SenderNodeID: nodeID,
		SenderName:   tm.config.DeviceName,
		TotalBytes:   totalBytes,
		Files:        manifestFiles,
	}

	manifestBytes, err := json.Marshal(manifest)
	if err != nil {
		tm.notifyComplete(batchID, false, err.Error())
		return err
	}

	targetBase := fmt.Sprintf("http://%s:%d", peerIP, port)

	// Step 1: Pre-flight batch request
	reqURL := fmt.Sprintf("%s/v1/transfer/batch/request", targetBase)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, bytes.NewReader(manifestBytes))
	if err != nil {
		tm.notifyComplete(batchID, false, err.Error())
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if nodeID != "" {
		req.Header.Set(HeaderSenderNodeID, nodeID)
	}

	resp, err := client.Do(req)
	if err != nil {
		tm.notifyComplete(batchID, false, err.Error())
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errMsg string
		switch resp.StatusCode {
		case http.StatusInsufficientStorage:
			errMsg = "peer has insufficient storage space (HTTP 507)"
		case http.StatusRequestTimeout:
			errMsg = "transfer approval timed out (HTTP 408)"
		case http.StatusForbidden:
			errMsg = "transfer rejected by user (HTTP 403)"
		default:
			body, _ := io.ReadAll(resp.Body)
			errMsg = fmt.Sprintf("batch request rejected: HTTP %d (%s)", resp.StatusCode, string(body))
		}
		err := errors.New(errMsg)
		tm.notifyComplete(batchID, false, errMsg)
		return err
	}

	// Step 2: Stream each file sequentially
	var batchTransferred int64
	totalFiles := len(sources)

	for idx, src := range sources {
		select {
		case <-ctx.Done():
			tm.notifyComplete(batchID, false, "transfer canceled")
			return ctx.Err()
		default:
		}

		var reader io.Reader
		var closer io.Closer

		if src.Reader != nil {
			reader = src.Reader
			if c, ok := src.Reader.(io.Closer); ok {
				closer = c
			}
		} else if src.FilePath != "" {
			f, err := os.Open(src.FilePath)
			if err != nil {
				tm.notifyComplete(batchID, false, fmt.Sprintf("cannot open %s: %v", src.FileName, err))
				return err
			}
			reader = f
			closer = f
		} else {
			err := fmt.Errorf("no source reader or path for file %s", src.FileName)
			tm.notifyComplete(batchID, false, err.Error())
			return err
		}

		streamURL := fmt.Sprintf("%s/v1/transfer/stream", targetBase)
		fileIdx := idx + 1
		fileBase := batchTransferred

		pw := &batchProgressReader{
			reader:          reader,
			fileTotal:       src.FileSize,
			batchID:         batchID,
			fileIndex:       fileIdx,
			totalFiles:      totalFiles,
			fileName:        src.FileName,
			batchBase:       fileBase,
			batchTotal:      totalBytes,
			onProgress:      tm.config.OnProgress,
			onBatchProgress: tm.config.OnBatchProgress,
		}

		streamReq, err := http.NewRequestWithContext(ctx, http.MethodPost, streamURL, pw)
		if err != nil {
			if closer != nil {
				_ = closer.Close()
			}
			tm.notifyComplete(batchID, false, err.Error())
			return err
		}

		streamReq.Header.Set(HeaderTransferID, src.FileID)
		streamReq.Header.Set(HeaderBatchID, batchID)
		streamReq.Header.Set(HeaderFileID, src.FileID)
		streamReq.Header.Set(HeaderFileName, src.FileName)
		streamReq.Header.Set(HeaderFileSize, strconv.FormatInt(src.FileSize, 10))
		streamReq.Header.Set(HeaderFileSHA256, src.SHA256)
		streamReq.Header.Set("Content-Type", "application/octet-stream")
		streamReq.ContentLength = src.FileSize

		streamResp, err := client.Do(streamReq)
		if closer != nil {
			_ = closer.Close()
		}

		if err != nil {
			tm.notifyComplete(batchID, false, fmt.Sprintf("file %s failed: %v", src.FileName, err))
			return err
		}

		if streamResp.StatusCode != http.StatusOK {
			bodyBytes, _ := io.ReadAll(streamResp.Body)
			_ = streamResp.Body.Close()
			err := fmt.Errorf("stream for file %s failed: HTTP %d (%s)", src.FileName, streamResp.StatusCode, string(bodyBytes))
			tm.notifyComplete(batchID, false, err.Error())
			return err
		}
		_ = streamResp.Body.Close()

		batchTransferred += src.FileSize
	}

	tm.notifyComplete(batchID, true, "")
	return nil
}

type batchProgressReader struct {
	reader          io.Reader
	fileTotal       int64
	fileCurrent     int64
	batchID         string
	fileIndex       int
	totalFiles      int
	fileName        string
	batchBase       int64
	batchTotal      int64
	onProgress      func(string, int64, int64)
	onBatchProgress func(string, int, int, string, int64, int64, int64, int64)
}

func (bpr *batchProgressReader) Read(p []byte) (int, error) {
	n, err := bpr.reader.Read(p)
	if n > 0 {
		bpr.fileCurrent += int64(n)
		currentBatchBytes := bpr.batchBase + bpr.fileCurrent
		if bpr.onBatchProgress != nil {
			bpr.onBatchProgress(
				bpr.batchID,
				bpr.fileIndex,
				bpr.totalFiles,
				bpr.fileName,
				bpr.fileCurrent,
				bpr.fileTotal,
				currentBatchBytes,
				bpr.batchTotal,
			)
		}
		if bpr.onProgress != nil {
			bpr.onProgress(bpr.batchID, currentBatchBytes, bpr.batchTotal)
		}
	}
	return n, err
}
