package core

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestTrustStore_AddAndRevoke(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "snowdrop-trust-test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	ts, err := NewTrustStore(tempDir)
	if err != nil {
		t.Fatalf("failed to create trust store: %v", err)
	}

	if ts.IsTrusted("node-123") {
		t.Errorf("expected node-123 to not be trusted initially")
	}

	if err := ts.AddTrusted("node-123", "MacBook Pro"); err != nil {
		t.Fatalf("failed to add trusted: %v", err)
	}

	if !ts.IsTrusted("node-123") {
		t.Errorf("expected node-123 to be trusted")
	}

	list := ts.List()
	if len(list) != 1 || list[0].NodeID != "node-123" || list[0].DeviceName != "MacBook Pro" {
		t.Errorf("unexpected list: %+v", list)
	}

	// Test persistence
	ts2, err := NewTrustStore(tempDir)
	if err != nil {
		t.Fatalf("failed to reload trust store: %v", err)
	}
	if !ts2.IsTrusted("node-123") {
		t.Errorf("expected node-123 to persist across reloads")
	}

	// Revoke
	if err := ts2.RevokeTrusted("node-123"); err != nil {
		t.Fatalf("failed to revoke: %v", err)
	}
	if ts2.IsTrusted("node-123") {
		t.Errorf("expected node-123 to be revoked")
	}
}

func TestTransferManager_ApprovalFlow(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "snowdrop-approval-test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	ts, _ := NewTrustStore(tempDir)
	approvedTransferID := "transfer-approved-1"

	var approvalFired bool
	cfg := &EngineConfig{
		DataDir:           tempDir,
		DownloadDir:       filepath.Join(tempDir, "downloads"),
		DeviceName:        "TestReceiver",
		RequireApproval:   true,
		AutoAcceptTrusted: true,
		OnIncomingApproval: func(transferID, nodeID, senderName, fileName string, fileSize int64) {
			approvalFired = true
		},
	}
	_ = approvalFired

	tm := NewTransferManager(cfg, ts)

	// Simulate pending approval
	ch := make(chan int, 1)
	tm.mu.Lock()
	tm.approvals[approvedTransferID] = ch
	tm.mu.Unlock()

	go func() {
		time.Sleep(50 * time.Millisecond)
		tm.ResolveApproval(approvedTransferID, ApprovalDecisionAccept)
	}()

	select {
	case dec := <-ch:
		if dec != ApprovalDecisionAccept {
			t.Errorf("expected Accept, got %d", dec)
		}
	case <-time.After(1 * time.Second):
		t.Fatalf("timed out waiting for approval resolution")
	}
}
