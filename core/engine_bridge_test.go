package core

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
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

func TestSetDownloadDir(t *testing.T) {
	d1 := t.TempDir()
	d2 := filepath.Join(t.TempDir(), "custom-downloads")

	eng, err := NewEngine(&EngineConfig{
		DataDir:     t.TempDir(),
		DownloadDir: d1,
		DeviceName:  "TestMac",
	})
	if err != nil {
		t.Fatalf("NewEngine failed: %v", err)
	}

	if err := eng.SetDownloadDir(""); err == nil {
		t.Fatal("expected error for empty download dir")
	}

	if err := eng.SetDownloadDir(d2); err != nil {
		t.Fatalf("SetDownloadDir failed: %v", err)
	}

	if got := eng.transfers.downloadDir(); got != d2 {
		t.Fatalf("expected transfer manager downloadDir %q, got %q", d2, got)
	}
	if _, err := os.Stat(d2); err != nil {
		t.Fatalf("expected directory %q to be created: %v", d2, err)
	}
}

func TestSetApprovalConfigConcurrent(t *testing.T) {
	eng, err := NewEngine(&EngineConfig{
		DataDir:           t.TempDir(),
		DownloadDir:       t.TempDir(),
		DeviceName:        "TestMac",
		RequireApproval:   true,
		AutoAcceptTrusted: true,
	})
	if err != nil {
		t.Fatalf("NewEngine failed: %v", err)
	}

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(2)
		go func(v bool) {
			defer wg.Done()
			eng.SetApprovalConfig(v, !v)
		}(i%2 == 0)
		go func() {
			defer wg.Done()
			_, _ = eng.transfers.approvalConfig()
			_ = eng.transfers.downloadDir()
		}()
	}
	wg.Wait()
}

func TestStopAndWait(t *testing.T) {
	var (
		mu         sync.Mutex
		lastStatus int
		lastMsg    string
	)
	eng, err := NewEngine(&EngineConfig{
		DataDir:     t.TempDir(),
		DownloadDir: t.TempDir(),
		DeviceName:  "TestMac",
		OnStatusChange: func(status int, message string) {
			mu.Lock()
			lastStatus = status
			lastMsg = message
			mu.Unlock()
		},
	})
	if err != nil {
		t.Fatalf("NewEngine failed: %v", err)
	}

	eng.wg.Add(1)
	go func() {
		defer eng.wg.Done()
		<-eng.ctx.Done()
		time.Sleep(40 * time.Millisecond)
	}()

	start := time.Now()
	eng.StopAndWait(2 * time.Second)
	elapsed := time.Since(start)
	if elapsed < 35*time.Millisecond {
		t.Fatalf("StopAndWait returned before worker finished (%v)", elapsed)
	}

	mu.Lock()
	defer mu.Unlock()
	if lastStatus != StatusDisconnected || lastMsg != "stopped" {
		t.Fatalf("expected StatusDisconnected/'stopped', got %d/%q", lastStatus, lastMsg)
	}
}

func TestSendFileNotStartedNotifiesComplete(t *testing.T) {
	var (
		mu      sync.Mutex
		gotID   string
		gotOK   = true
		gotErr  string
	)
	eng, err := NewEngine(&EngineConfig{
		DataDir:     t.TempDir(),
		DownloadDir: t.TempDir(),
		DeviceName:  "TestMac",
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			mu.Lock()
			gotID = transferID
			gotOK = success
			gotErr = errorMsg
			mu.Unlock()
		},
	})
	if err != nil {
		t.Fatalf("NewEngine failed: %v", err)
	}

	if err := eng.SendFile("127.0.0.1", "/tmp/nonexistent", "tx-unstarted"); err == nil {
		t.Fatal("expected SendFile error when tsServer is nil")
	}

	mu.Lock()
	defer mu.Unlock()
	if gotID != "tx-unstarted" || gotOK || gotErr == "" {
		t.Fatalf("expected failure completion callback for tx-unstarted, got id=%q ok=%v err=%q", gotID, gotOK, gotErr)
	}
}

func TestApprovalDismissedOnSenderCancel(t *testing.T) {
	dismissed := make(chan struct {
		id     string
		reason string
	}, 1)

	cfg := &EngineConfig{
		DeviceName:      "Receiver",
		DataDir:         t.TempDir(),
		DownloadDir:     t.TempDir(),
		RequireApproval: true,
		OnIncomingApproval: func(transferID, senderNodeID, senderName, fileName string, sizeBytes int64) {
		},
		OnApprovalDismissed: func(transferID, reason string) {
			dismissed <- struct {
				id     string
				reason string
			}{transferID, reason}
		},
	}

	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-node"))
	defer server.Close()

	payload := []byte("hello")
	sum := sha256.Sum256(payload)
	reqCtx, cancel := context.WithCancel(context.Background())

	req, _ := http.NewRequestWithContext(reqCtx, http.MethodPost, server.URL+"/v1/transfer/request", nil)
	req.Header.Set(HeaderTransferID, "tx-dismiss-1")
	req.Header.Set(HeaderFileName, "hello.txt")
	req.Header.Set(HeaderFileSize, strconv.Itoa(len(payload)))
	req.Header.Set(HeaderFileSHA256, hex.EncodeToString(sum[:]))
	req.Header.Set(HeaderSenderName, "Sender")

	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	_, _ = server.Client().Do(req)

	select {
	case ev := <-dismissed:
		if ev.id != "tx-dismiss-1" || ev.reason != "sender_disconnected" {
			t.Fatalf("unexpected dismissal event: %+v", ev)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for OnApprovalDismissed")
	}

	// Silence unused bytes import if needed
	_ = bytes.NewReader(payload)
}

func TestZeroByteBatchAcceptedAndExpiredEntriesPruned(t *testing.T) {
	dlDir := t.TempDir()
	cfg := &EngineConfig{
		DeviceName:  "Receiver",
		DataDir:     t.TempDir(),
		DownloadDir: dlDir,
	}
	tm := NewTransferManager(cfg)
	server := httptest.NewServer(tm.Router("receiver-node"))
	defer server.Close()

	// Seed expired pending and batch entries and verify pruneExpiredLocked removes them.
	tm.mu.Lock()
	tm.pending["stale-pending"] = &TransferRequest{TransferID: "stale-pending", CreatedAt: time.Now().Add(-20 * time.Minute)}
	tm.batches["stale-batch"] = &BatchSession{CreatedAt: time.Now().Add(-20 * time.Minute)}
	tm.mu.Unlock()

	emptyHash := sha256.Sum256(nil)
	err := tm.SendBatch(
		context.Background(),
		server.Client(),
		"127.0.0.1",
		server.Listener.Addr().(*net.TCPAddr).Port,
		"zero-batch-1",
		[]BatchSendSource{
			{
				FileID:   "f-1",
				FileName: "empty.txt",
				FileSize: 0,
				SHA256:   hex.EncodeToString(emptyHash[:]),
				Reader:   bytes.NewReader(nil),
			},
		},
	)
	if err != nil {
		t.Fatalf("expected 0-byte batch to succeed, got: %v", err)
	}

	tm.mu.RLock()
	_, hasStalePending := tm.pending["stale-pending"]
	_, hasStaleBatch := tm.batches["stale-batch"]
	tm.mu.RUnlock()
	if hasStalePending || hasStaleBatch {
		t.Fatalf("expected stale entries pruned, pending=%v batch=%v", hasStalePending, hasStaleBatch)
	}

	saved, err := os.ReadFile(filepath.Join(dlDir, "empty.txt"))
	if err != nil || len(saved) != 0 {
		t.Fatalf("expected 0-byte file on disk, got err=%v len=%d", err, len(saved))
	}
}
