package core

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
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


