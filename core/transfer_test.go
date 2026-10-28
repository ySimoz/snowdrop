package core

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"
)

func TestNodeInfoEndpoint(t *testing.T) {
	cfg := &EngineConfig{
		DeviceName:  "TestNode",
		DataDir:     t.TempDir(),
		DownloadDir: t.TempDir(),
	}
	tm := NewTransferManager(cfg)
	router := tm.Router("node-123")

	req := httptest.NewRequest(http.MethodGet, "/v1/info", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var info NodeInfo
	if err := json.Unmarshal(w.Body.Bytes(), &info); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if info.NodeID != "node-123" || info.DeviceName != "TestNode" || info.ProtocolVersion != ProtocolVersion {
		t.Fatalf("unexpected info response: %+v", info)
	}
}

func TestTransferSuccess(t *testing.T) {
	dlDir := t.TempDir()
	var (
		mu           sync.Mutex
		progressHits int
		completedID  string
		completedOK  bool
	)

	cfg := &EngineConfig{
		DeviceName:  "Receiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
		OnIncomingRequest: func(transferID string, senderName string, fileName string, sizeBytes int64) bool {
			return true
		},
		OnProgress: func(transferID string, bytesTransferred int64, totalBytes int64) {
			mu.Lock()
			progressHits++
			mu.Unlock()
		},
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			mu.Lock()
			completedID = transferID
			completedOK = success
			mu.Unlock()
		},
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-node"))
	defer server.Close()

	// 1 MB test payload
	payloadSize := int64(1024 * 1024)
	payload := make([]byte, payloadSize)
	_, _ = rand.Read(payload)

	hash := sha256.Sum256(payload)
	hashHex := hex.EncodeToString(hash[:])
	transferID := "test-transfer-1"

	// 1. Request
	req, err := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/request", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(HeaderTransferID, transferID)
	req.Header.Set(HeaderFileName, "sample.bin")
	req.Header.Set(HeaderFileSize, strconv.FormatInt(payloadSize, 10))
	req.Header.Set(HeaderFileSHA256, hashHex)
	req.Header.Set(HeaderSenderName, "SenderNode")

	resp, err := server.Client().Do(req)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", resp.StatusCode)
	}

	// 2. Stream
	streamReq, err := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/stream", bytes.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	streamReq.Header.Set(HeaderTransferID, transferID)
	streamResp, err := server.Client().Do(streamReq)
	if err != nil {
		t.Fatalf("stream failed: %v", err)
	}
	_ = streamResp.Body.Close()
	if streamResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", streamResp.StatusCode)
	}

	mu.Lock()
	defer mu.Unlock()
	if !completedOK || completedID != transferID {
		t.Fatalf("expected complete success, got ID=%s OK=%v", completedID, completedOK)
	}
	if progressHits == 0 {
		t.Fatal("expected progress updates")
	}

	// Verify file on disk
	receivedFile := filepath.Join(dlDir, "sample.bin")
	data, err := os.ReadFile(receivedFile)
	if err != nil {
		t.Fatalf("failed reading saved file: %v", err)
	}
	if !bytes.Equal(data, payload) {
		t.Fatal("saved payload does not match sent bytes")
	}
}

func TestTransferHashMismatch(t *testing.T) {
	dlDir := t.TempDir()
	var (
		mu           sync.Mutex
		completedOK  bool
		completedErr string
	)

	cfg := &EngineConfig{
		DeviceName:  "Receiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			mu.Lock()
			completedOK = success
			completedErr = errorMsg
			mu.Unlock()
		},
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-node"))
	defer server.Close()

	payload := []byte("hello corrupt stream")
	badHashHex := "0000000000000000000000000000000000000000000000000000000000000000"
	transferID := "corrupt-transfer"

	req, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/request", nil)
	req.Header.Set(HeaderTransferID, transferID)
	req.Header.Set(HeaderFileName, "corrupt.txt")
	req.Header.Set(HeaderFileSize, strconv.Itoa(len(payload)))
	req.Header.Set(HeaderFileSHA256, badHashHex)

	resp, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	streamReq, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/stream", bytes.NewReader(payload))
	streamReq.Header.Set(HeaderTransferID, transferID)
	streamResp, err := server.Client().Do(streamReq)
	if err != nil {
		t.Fatal(err)
	}
	_ = streamResp.Body.Close()
	if streamResp.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request on hash mismatch, got %d", streamResp.StatusCode)
	}

	mu.Lock()
	defer mu.Unlock()
	if completedOK {
		t.Fatal("expected transfer failure")
	}
	if completedErr == "" {
		t.Fatal("expected error message in callback")
	}

	// Verify temp file cleaned up
	files, _ := os.ReadDir(dlDir)
	if len(files) != 0 {
		t.Fatalf("expected 0 files in download dir, found %d", len(files))
	}
}

func TestTransferSendHelper(t *testing.T) {
	dlDir := t.TempDir()
	cfg := &EngineConfig{
		DeviceName:  "PeerA",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("peer-a"))
	defer server.Close()

	// Create temp file to send
	srcFile := filepath.Join(t.TempDir(), "document.txt")
	content := []byte("snowdrop transmission payload")
	if err := os.WriteFile(srcFile, content, 0644); err != nil {
		t.Fatal(err)
	}

	tcpAddr := server.Listener.Addr().(*net.TCPAddr)
	port := tcpAddr.Port
	host := "127.0.0.1"

	// Use SendFile directly with the test server
	senderCfg := &EngineConfig{
		DeviceName: "PeerB",
	}
	senderTM := NewTransferManager(senderCfg)

	err := senderTM.SendFile(context.Background(), server.Client(), host, port, srcFile, "send-helper-1")
	if err != nil {
		t.Fatalf("SendFile failed: %v", err)
	}

	// Check received file
	savedFile := filepath.Join(dlDir, "document.txt")
	savedBytes, err := os.ReadFile(savedFile)
	if err != nil {
		t.Fatalf("cannot read saved file: %v", err)
	}
	if !bytes.Equal(savedBytes, content) {
		t.Fatal("saved content does not match source")
	}
}

func TestResolveUniquePath(t *testing.T) {
	dir := t.TempDir()
	p1 := resolveUniquePath(dir, "report.pdf")
	if err := os.WriteFile(p1, []byte("1"), 0644); err != nil {
		t.Fatal(err)
	}

	p2 := resolveUniquePath(dir, "report.pdf")
	expected2 := filepath.Join(dir, "report (1).pdf")
	if p2 != expected2 {
		t.Fatalf("expected %s, got %s", expected2, p2)
	}
}

func TestTransferCancellationMidStream(t *testing.T) {
	dlDir := t.TempDir()
	var (
		mu           sync.Mutex
		completedOK  bool
		completedErr string
		canceledID   = "cancel-test-1"
	)

	cfg := &EngineConfig{
		DeviceName:  "Receiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			mu.Lock()
			completedOK = success
			completedErr = errorMsg
			mu.Unlock()
		},
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-cancel-node"))
	defer server.Close()

	// 10 MB payload
	payloadSize := int64(10 * 1024 * 1024)
	dummyHash := "1111111111111111111111111111111111111111111111111111111111111111"

	// 1. Request
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/request", nil)
	req.Header.Set(HeaderTransferID, canceledID)
	req.Header.Set(HeaderFileName, "large.bin")
	req.Header.Set(HeaderFileSize, strconv.FormatInt(payloadSize, 10))
	req.Header.Set(HeaderFileSHA256, dummyHash)
	req.Header.Set(HeaderSenderName, "SenderNode")

	resp, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	// 2. Stream using pipe that feeds bytes slowly then cancels receiver
	pr, pw := io.Pipe()
	go func() {
		defer pw.Close()
		buf := make([]byte, 64*1024)
		// Write 2 chunks
		_, _ = pw.Write(buf)
		_, _ = pw.Write(buf)
		// Cancel on receiver side
		tm.Cancel(canceledID)
	}()

	streamReq, _ := http.NewRequest(http.MethodPost, server.URL+"/v1/transfer/stream", pr)
	streamReq.Header.Set(HeaderTransferID, canceledID)
	streamResp, _ := server.Client().Do(streamReq)
	if streamResp != nil {
		_ = streamResp.Body.Close()
	}

	mu.Lock()
	ok := completedOK
	errStr := completedErr
	mu.Unlock()

	if ok {
		t.Fatal("expected transfer to not succeed after cancellation")
	}
	if errStr == "" {
		t.Fatal("expected error message on cancellation")
	}

	// Ensure no lingering .part files or target files in download dir
	files, err := os.ReadDir(dlDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 0 {
		t.Fatalf("expected download dir to be clean after cancel, found %d files", len(files))
	}
}

func TestTransferSenderCancellation(t *testing.T) {
	dlDir := t.TempDir()
	doneCh := make(chan struct{})
	cfg := &EngineConfig{
		DeviceName:  "Receiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			select {
			case <-doneCh:
			default:
				close(doneCh)
			}
		},
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-node"))
	defer server.Close()

	senderCfg := &EngineConfig{DeviceName: "Sender"}
	senderTM := NewTransferManager(senderCfg)

	tcpAddr := server.Listener.Addr().(*net.TCPAddr)
	transferID := "sender-cancel-test"

	pr, pw := io.Pipe()
	go func() {
		buf := make([]byte, 64*1024)
		_, _ = pw.Write(buf)
		time.Sleep(50 * time.Millisecond)
		// Cancel from sender side
		senderTM.Cancel(transferID)
		pw.Close()
	}()

	err := senderTM.SendStream(
		context.Background(),
		server.Client(),
		"127.0.0.1",
		tcpAddr.Port,
		pr,
		"interrupted.bin",
		10*1024*1024,
		"dummyhash",
		transferID,
	)

	if err == nil {
		t.Fatal("expected error on sender cancellation, got nil")
	}

	select {
	case <-doneCh:
	case <-time.After(2 * time.Second):
	}

	// Ensure no temporary files remained
	files, _ := os.ReadDir(dlDir)
	if len(files) != 0 {
		t.Fatalf("expected 0 files after sender cancellation, found %d: %v", len(files), files[0].Name())
	}
}

// repeatingReader generates deterministic data on the fly without memory allocation
type repeatingReader struct {
	pattern []byte
	idx     int
}

func (r *repeatingReader) Read(p []byte) (n int, err error) {
	for i := range p {
		p[i] = r.pattern[r.idx]
		r.idx = (r.idx + 1) % len(r.pattern)
	}
	return len(p), nil
}

func TestTransferLargeStreamStreaming(t *testing.T) {
	dlDir := t.TempDir()
	cfg := &EngineConfig{
		DeviceName:  "LargeReceiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("large-receiver"))
	defer server.Close()

	senderCfg := &EngineConfig{DeviceName: "LargeSender"}
	senderTM := NewTransferManager(senderCfg)

	tcpAddr := server.Listener.Addr().(*net.TCPAddr)
	transferID := "large-stream-test"

	// 25 MB virtual stream without in-memory allocation
	streamSize := int64(25 * 1024 * 1024)
	pattern := []byte("SnowdropHighThroughputChunkStreamingVerification!")

	// Pre-calculate SHA-256 by streaming through hasher
	h := sha256.New()
	_, err := io.Copy(h, io.LimitReader(&repeatingReader{pattern: pattern}, streamSize))
	if err != nil {
		t.Fatal(err)
	}
	expectedHash := hex.EncodeToString(h.Sum(nil))

	// Stream to receiver
	streamSource := io.LimitReader(&repeatingReader{pattern: pattern}, streamSize)
	err = senderTM.SendStream(
		context.Background(),
		server.Client(),
		"127.0.0.1",
		tcpAddr.Port,
		streamSource,
		"large-stream.bin",
		streamSize,
		expectedHash,
		transferID,
	)

	if err != nil {
		t.Fatalf("SendStream failed for large stream: %v", err)
	}

	// Verify file size on disk matches
	savedPath := filepath.Join(dlDir, "large-stream.bin")
	fi, err := os.Stat(savedPath)
	if err != nil {
		t.Fatalf("target file not found: %v", err)
	}
	if fi.Size() != streamSize {
		t.Fatalf("expected file size %d, got %d", streamSize, fi.Size())
	}
}




