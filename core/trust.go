package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// TrustedPeer represents a remembered peer that is allowed to transfer files
type TrustedPeer struct {
	NodeID     string    `json:"node_id"`
	DeviceName string    `json:"device_name"`
	AddedAt    time.Time `json:"added_at"`
	AutoAccept bool      `json:"auto_accept"`
}

// TrustStore manages persistent storage of trusted peers in DataDir
type TrustStore struct {
	filePath string
	mu       sync.RWMutex
	peers    map[string]TrustedPeer
}

// NewTrustStore loads or initializes the trust store
func NewTrustStore(dataDir string) (*TrustStore, error) {
	ts := &TrustStore{
		filePath: filepath.Join(dataDir, "trusted_peers.json"),
		peers:    make(map[string]TrustedPeer),
	}
	_ = ts.load()
	return ts, nil
}

func (ts *TrustStore) load() error {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	data, err := os.ReadFile(ts.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	var list []TrustedPeer
	if err := json.Unmarshal(data, &list); err != nil {
		return err
	}

	ts.peers = make(map[string]TrustedPeer, len(list))
	for _, p := range list {
		ts.peers[p.NodeID] = p
	}
	return nil
}

func (ts *TrustStore) saveLocked() error {
	list := make([]TrustedPeer, 0, len(ts.peers))
	for _, p := range ts.peers {
		list = append(list, p)
	}

	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return err
	}

	tmpFile := ts.filePath + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0600); err != nil {
		return err
	}
	return os.Rename(tmpFile, ts.filePath)
}

// IsTrusted checks whether a node is trusted and has auto-accept enabled
func (ts *TrustStore) IsTrusted(nodeID string) bool {
	if nodeID == "" {
		return false
	}
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	peer, exists := ts.peers[nodeID]
	return exists && peer.AutoAccept
}

// AddTrusted records a new peer into the trust store
func (ts *TrustStore) AddTrusted(nodeID, deviceName string) error {
	if nodeID == "" {
		return nil
	}
	ts.mu.Lock()
	defer ts.mu.Unlock()

	ts.peers[nodeID] = TrustedPeer{
		NodeID:     nodeID,
		DeviceName: deviceName,
		AddedAt:    time.Now(),
		AutoAccept: true,
	}
	return ts.saveLocked()
}

// RevokeTrusted removes a peer from the trust store
func (ts *TrustStore) RevokeTrusted(nodeID string) error {
	ts.mu.Lock()
	defer ts.mu.Unlock()

	delete(ts.peers, nodeID)
	return ts.saveLocked()
}

// List returns all currently trusted peers
func (ts *TrustStore) List() []TrustedPeer {
	ts.mu.RLock()
	defer ts.mu.RUnlock()

	list := make([]TrustedPeer, 0, len(ts.peers))
	for _, p := range ts.peers {
		list = append(list, p)
	}
	return list
}
