package core

import (
	"testing"
)

func TestBaseDeviceKey(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"motorola-edge-40-neo", "motorola-edge-40-neo"},
		{"motorola-edge-40-neo-1", "motorola-edge-40-neo"},
		{"motorola-edge-40-neo-22", "motorola-edge-40-neo"},
		{"MacBook-Pro", "macbook-pro"},
		{"macbook-pro-1", "macbook-pro"},
		{"device", "device"},
	}

	for _, tc := range tests {
		got := baseDeviceKey(tc.input)
		if got != tc.expected {
			t.Errorf("baseDeviceKey(%q) = %q; want %q", tc.input, got, tc.expected)
		}
	}
}

func TestDeduplicatePeers(t *testing.T) {
	peers := []PeerInfo{
		{
			ID:       "node-old",
			HostName: "motorola-edge-40-neo",
			Online:   false,
		},
		{
			ID:       "node-new",
			HostName: "motorola-edge-40-neo-1",
			Online:   true,
		},
		{
			ID:       "macbook",
			HostName: "macbook-pro",
			Online:   true,
		},
		{
			ID:       "ipad",
			HostName: "ipad-mini",
			Online:   false,
		},
	}

	deduped := deduplicatePeers(peers)

	if len(deduped) != 3 {
		t.Fatalf("expected 3 peers after deduplication, got %d", len(deduped))
	}

	// Ensure the old offline motorola was removed
	for _, p := range deduped {
		if p.ID == "node-old" {
			t.Errorf("expected node-old to be suppressed, but it was present")
		}
	}

	// Ensure standalone offline device (ipad) is preserved
	hasIpad := false
	for _, p := range deduped {
		if p.ID == "ipad" {
			hasIpad = true
		}
	}
	if !hasIpad {
		t.Errorf("expected standalone offline peer (ipad) to be preserved")
	}
}
