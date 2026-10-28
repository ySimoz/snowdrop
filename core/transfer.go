package core

import (
	"context"
	"crypto/sha256"
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
	"sync"
	"time"
)

// TransferManager coordinates incoming and outgoing transfers
type TransferManager struct {
	config    *EngineConfig
	mu        sync.RWMutex
	pending   map[string]*TransferRequest
	cancels   map[string]context.CancelFunc
	activeCnt int
}

func NewTransferManager(cfg *EngineConfig) *TransferManager {
	return &TransferManager{
		config:  cfg,
		pending: make(map[string]*TransferRequest),
		cancels: make(map[string]context.CancelFunc),
	}
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
		fileName := r.Header.Get(HeaderFileName)
		sizeStr := r.Header.Get(HeaderFileSize)
		fileHash := r.Header.Get(HeaderFileSHA256)
		senderName := r.Header.Get(HeaderSenderName)

		if transferID == "" || fileName == "" || sizeStr == "" || fileHash == "" {
			http.Error(w, "missing required transfer headers", http.StatusBadRequest)
			return
		}

		sizeBytes, err := strconv.ParseInt(sizeStr, 10, 64)
		if err != nil || sizeBytes < 0 {
			http.Error(w, "invalid file size", http.StatusBadRequest)
			return
		}

		tm.mu.Lock()
		if _, exists := tm.pending[transferID]; exists {
			tm.mu.Unlock()
			http.Error(w, "transfer id conflict", http.StatusConflict)
			return
		}
		req := &TransferRequest{
			TransferID: transferID,
			FileName:   filepath.Base(fileName),
			FileSize:   sizeBytes,
			SHA256:     fileHash,
			SenderName: senderName,
			CreatedAt:  time.Now(),
		}
		tm.pending[transferID] = req
		tm.mu.Unlock()

		accepted := true
		if tm.config.OnIncomingRequest != nil {
			accepted = tm.config.OnIncomingRequest(transferID, senderName, req.FileName, sizeBytes)
		}

		if !accepted {
			tm.mu.Lock()
			delete(tm.pending, transferID)
			tm.mu.Unlock()
			http.Error(w, "transfer rejected", http.StatusForbidden)
			return
		}

		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("POST /v1/transfer/stream", func(w http.ResponseWriter, r *http.Request) {
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
		tempFile, err := os.OpenFile(tempPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			msg := fmt.Sprintf("cannot create temporary file: %v", err)
			if tm.config.OnTransferComplete != nil {
				tm.config.OnTransferComplete(transferID, false, msg)
			}
			http.Error(w, msg, http.StatusInternalServerError)
			return
		}

		defer func() {
			_ = tempFile.Close()
			if _, statErr := os.Stat(tempPath); statErr == nil {
				_ = os.Remove(tempPath)
			}
		}()

		hasher := sha256.New()
		buf := make([]byte, BufferSize)
		var transferred int64

		for {
			select {
			case <-ctx.Done():
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
		if calcHash != req.SHA256 {
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
			tm.config.OnTransferComplete(transferID, true, "")
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

func resolveUniquePath(dir, filename string) string {
	candidate := filepath.Join(dir, filename)
	if _, err := os.Stat(candidate); os.IsNotExist(err) {
		return candidate
	}

	ext := filepath.Ext(filename)
	base := filename[:len(filename)-len(ext)]
	counter := 1
	for {
		candidate = filepath.Join(dir, fmt.Sprintf("%s (%d)%s", base, counter, ext))
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
		counter++
	}
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
