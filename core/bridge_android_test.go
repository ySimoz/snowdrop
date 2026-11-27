package core

import (
	"encoding/json"
	"os"
	"sync"
	"testing"
)

type mockAndroidCallback struct {
	mu                 sync.Mutex
	dismissedID        string
	dismissedReason    string
	completedID        string
	completedSuccess   bool
	completedErrorMsgs []string
}

func (m *mockAndroidCallback) OnStatusChange(int, string)                                      {}
func (m *mockAndroidCallback) OnAuthRequired(string)                                           {}
func (m *mockAndroidCallback) OnPeersUpdated(string)                                           {}
func (m *mockAndroidCallback) OnProgress(string, int64, int64)                                 {}
func (m *mockAndroidCallback) OnIncomingApproval(string, string, string, string, int64)        {}
func (m *mockAndroidCallback) OnBatchProgress(string, int, int, string, int64, int64, int64, int64) {}
func (m *mockAndroidCallback) OnBatchFileComplete(string, int, int, string, string)            {}

func (m *mockAndroidCallback) OnTransferComplete(id string, ok bool, errMsg string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.completedID = id
	m.completedSuccess = ok
	m.completedErrorMsgs = append(m.completedErrorMsgs, errMsg)
}

func (m *mockAndroidCallback) OnApprovalDismissed(id string, reason string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.dismissedID = id
	m.dismissedReason = reason
}

func TestAndroidBridgeLifecycleAndApprovalDismissed(t *testing.T) {
	StopAndroidEngine()
	defer StopAndroidEngine()

	cb := &mockAndroidCallback{}
	if err := StartAndroidEngine(t.TempDir(), t.TempDir(), "TestPixel", cb); err != nil {
		t.Fatalf("StartAndroidEngine failed: %v", err)
	}

	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()
	if eng == nil || eng.config.OnApprovalDismissed == nil {
		t.Fatalf("expected active androidEngine with OnApprovalDismissed callback")
	}

	eng.config.OnApprovalDismissed("tx-123", "timeout")

	cb.mu.Lock()
	gotID, gotReason := cb.dismissedID, cb.dismissedReason
	cb.mu.Unlock()
	if gotID != "tx-123" || gotReason != "timeout" {
		t.Fatalf("unexpected dismissed callback: id=%q reason=%q", gotID, gotReason)
	}

	StopAndroidEngine()

	androidMu.Lock()
	afterStop := androidEngine
	androidMu.Unlock()
	if afterStop != nil {
		t.Fatalf("expected androidEngine nil after StopAndroidEngine")
	}
}

func TestAndroidSendClosesFDsWhenEngineStopped(t *testing.T) {
	StopAndroidEngine()

	r1, w1, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe failed: %v", err)
	}
	defer w1.Close()

	// SendFileToPeer takes ownership of r1 FD and must close it when engine is nil.
	fd1 := int(r1.Fd())
	SendFileToPeer("100.64.0.1", fd1, "a.txt", 10, "tx-nil")
	if _, writeErr := w1.Write([]byte("ping")); writeErr == nil {
		t.Fatalf("expected write to pipe fail after SendFileToPeer closed FD")
	}

	r2, w2, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe 2 failed: %v", err)
	}
	defer w2.Close()

	payload, _ := json.Marshal([]androidBatchItem{{FD: int(r2.Fd()), Name: "b.txt", Size: 4}})
	SendBatchToPeer("100.64.0.1", "batch-nil", string(payload))
	if _, writeErr := w2.Write([]byte("ping")); writeErr == nil {
		t.Fatalf("expected write to pipe fail after SendBatchToPeer closed FD")
	}
}
