package core

import "time"

// Engine status constants
const (
	StatusDisconnected = 0
	StatusNeedsAuth    = 1
	StatusConnecting   = 2
	StatusConnected    = 3
	StatusError        = 4
)

// Transfer protocol constants
const (
	DefaultPort        = 52445
	ProtocolVersion    = 1
	BufferSize         = 64 * 1024 // 64 KB chunk size
	HeaderTransferID   = "X-Transfer-ID"
	HeaderFileName     = "X-File-Name"
	HeaderFileSize     = "X-File-Size"
	HeaderFileSHA256   = "X-File-SHA256"
	HeaderSenderName   = "X-Sender-Name"
)

// PeerInfo describes a reachable peer on the Tailnet
type PeerInfo struct {
	ID          string   `json:"id"`
	HostName    string   `json:"hostName"`
	DNSName     string   `json:"dnsName"`
	OS          string   `json:"os"`
	IPAddresses []string `json:"ipAddresses"`
	Online      bool     `json:"online"`
}

// EngineConfig holds configuration and callbacks for the core engine
type EngineConfig struct {
	DataDir            string
	DownloadDir        string
	DeviceName         string
	Port               int
	OnStatusChange     func(status int, message string)
	OnAuthRequired     func(authURL string)
	OnPeersUpdated     func(peersJSON string)
	OnIncomingRequest  func(transferID string, senderName string, fileName string, sizeBytes int64) bool
	OnProgress         func(transferID string, bytesTransferred int64, totalBytes int64)
	OnTransferComplete func(transferID string, success bool, errorMsg string)
}

// NodeInfo represents the payload for GET /v1/info
type NodeInfo struct {
	NodeID          string `json:"nodeId"`
	DeviceName      string `json:"deviceName"`
	OS              string `json:"os"`
	ProtocolVersion int    `json:"protocolVersion"`
}

// TransferRequest represents an accepted or pending transfer
type TransferRequest struct {
	TransferID string    `json:"transferId"`
	FileName   string    `json:"fileName"`
	FileSize   int64     `json:"fileSize"`
	SHA256     string    `json:"sha256"`
	SenderName string    `json:"senderName"`
	CreatedAt  time.Time `json:"createdAt"`
}
