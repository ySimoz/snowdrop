package core

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"sync"

	"github.com/wlynxg/anet"
	"tailscale.com/net/netmon"
)

func init() {
	netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) {
		ifaces, err := anet.Interfaces()
		if err != nil || len(ifaces) == 0 {
			return []netmon.Interface{
				{
					Interface: &net.Interface{
						Index: 1,
						MTU:   1500,
						Name:  "lo",
						Flags: net.FlagUp | net.FlagLoopback,
					},
				},
			}, nil
		}

		var res []netmon.Interface
		for i := range ifaces {
			iface := ifaces[i]
			var addrs []net.Addr
			if a, err := anet.InterfaceAddrsByInterface(&iface); err == nil {
				addrs = a
			}
			res = append(res, netmon.Interface{
				Interface: &iface,
				AltAddrs:  addrs,
			})
		}
		return res, nil
	})
}

// AndroidCallback defines the gomobile callback interface
type AndroidCallback interface {
	OnStatusChange(status int, message string)
	OnAuthRequired(authURL string)
	OnPeersUpdated(peersJSON string)
	OnProgress(transferId string, current int64, total int64)
	OnTransferComplete(transferId string, success bool, errorMsg string)
	OnIncomingApproval(transferId string, senderNodeId string, senderName string, fileName string, fileSize int64)
	OnBatchProgress(batchId string, fileIndex int, totalFiles int, fileName string, fileCurrent int64, fileTotal int64, batchCurrent int64, batchTotal int64)
	OnBatchFileComplete(batchId string, fileIndex int, totalFiles int, fileName string, filePath string)
}

var (
	androidMu     sync.Mutex
	androidEngine *Engine
)

// StartAndroidEngine initializes and starts the core engine on Android
func StartAndroidEngine(dataDir string, downloadDir string, deviceName string, cb AndroidCallback) error {
	androidMu.Lock()
	if androidEngine != nil {
		androidMu.Unlock()
		return nil
	}
	androidMu.Unlock()

	cfg := &EngineConfig{
		DataDir:     dataDir,
		DownloadDir: downloadDir,
		DeviceName:  deviceName,
		OnStatusChange: func(status int, message string) {
			if cb != nil {
				cb.OnStatusChange(status, message)
			}
		},
		OnAuthRequired: func(authURL string) {
			if cb != nil {
				cb.OnAuthRequired(authURL)
			}
		},
		OnPeersUpdated: func(peersJSON string) {
			if cb != nil {
				cb.OnPeersUpdated(peersJSON)
			}
		},
		OnProgress: func(transferID string, bytesTransferred int64, totalBytes int64) {
			if cb != nil {
				cb.OnProgress(transferID, bytesTransferred, totalBytes)
			}
		},
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			if cb != nil {
				cb.OnTransferComplete(transferID, success, errorMsg)
			}
		},
		RequireApproval:   true,
		AutoAcceptTrusted: true,
		OnIncomingApproval: func(transferID string, senderNodeID string, senderName string, fileName string, sizeBytes int64) {
			if cb != nil {
				cb.OnIncomingApproval(transferID, senderNodeID, senderName, fileName, sizeBytes)
			}
		},
		OnBatchProgress: func(batchID string, fileIndex int, totalFiles int, fileName string, fileBytes int64, fileTotal int64, batchBytes int64, batchTotal int64) {
			if cb != nil {
				cb.OnBatchProgress(batchID, fileIndex, totalFiles, fileName, fileBytes, fileTotal, batchBytes, batchTotal)
			}
		},
		OnBatchFileReceived: func(batchID string, fileIndex int, totalFiles int, fileName string, filePath string) {
			if cb != nil {
				cb.OnBatchFileComplete(batchID, fileIndex, totalFiles, fileName, filePath)
			}
		},
	}

	eng, err := NewEngine(cfg)
	if err != nil {
		return err
	}

	if err := eng.Start(); err != nil {
		return err
	}

	androidMu.Lock()
	androidEngine = eng
	androidMu.Unlock()
	return nil
}

// StopAndroidEngine stops the active Android engine
func StopAndroidEngine() {
	androidMu.Lock()
	eng := androidEngine
	androidEngine = nil
	androidMu.Unlock()

	if eng != nil {
		eng.Stop()
	}
}

// SendFileToPeer sends a file via its Android file descriptor
func SendFileToPeer(peerIP string, fileDescriptor int, fileName string, fileSize int64, transferID string) {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng == nil {
		return
	}

	go func() {
		file := os.NewFile(uintptr(fileDescriptor), fileName)
		if file == nil {
			eng.transfers.notifyComplete(transferID, false, "invalid file descriptor")
			return
		}
		defer file.Close()

		// Compute SHA-256
		hasher := sha256.New()
		buf := make([]byte, BufferSize)
		if _, err := io.CopyBuffer(hasher, io.LimitReader(file, fileSize), buf); err != nil {
			eng.transfers.notifyComplete(transferID, false, fmt.Sprintf("checksum error: %v", err))
			return
		}
		hashHex := hex.EncodeToString(hasher.Sum(nil))

		// Seek back to beginning
		if _, err := file.Seek(0, io.SeekStart); err != nil {
			eng.transfers.notifyComplete(transferID, false, fmt.Sprintf("seek error: %v", err))
			return
		}

		if eng.tsServer == nil {
			eng.transfers.notifyComplete(transferID, false, "tsnet server not ready")
			return
		}

		client := eng.tsServer.HTTPClient()
		sanitizedName := sanitizeHostname(eng.config.DeviceName)
		serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)
		_ = eng.transfers.SendStream(
			eng.ctx,
			client,
			peerIP,
			eng.config.Port,
			file,
			fileName,
			fileSize,
			hashHex,
			transferID,
			serverHostname,
		)
	}()
}

type androidBatchItem struct {
	FD   int    `json:"fd"`
	Name string `json:"name"`
	Size int64  `json:"size"`
}

// SendBatchToPeer sends multiple files via Android file descriptors
func SendBatchToPeer(peerIP string, batchID string, filesJSON string) {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng == nil {
		return
	}

	go func() {
		var items []androidBatchItem
		if err := json.Unmarshal([]byte(filesJSON), &items); err != nil {
			eng.transfers.notifyComplete(batchID, false, fmt.Sprintf("invalid batch json: %v", err))
			return
		}

		if len(items) == 0 {
			eng.transfers.notifyComplete(batchID, false, "empty batch")
			return
		}

		var sources []BatchSendSource
		var filesToClose []*os.File

		defer func() {
			for _, f := range filesToClose {
				_ = f.Close()
			}
		}()

		for i, it := range items {
			file := os.NewFile(uintptr(it.FD), it.Name)
			if file == nil {
				eng.transfers.notifyComplete(batchID, false, fmt.Sprintf("invalid fd for %s", it.Name))
				return
			}
			filesToClose = append(filesToClose, file)

			hasher := sha256.New()
			buf := make([]byte, BufferSize)
			if _, err := io.CopyBuffer(hasher, io.LimitReader(file, it.Size), buf); err != nil {
				eng.transfers.notifyComplete(batchID, false, fmt.Sprintf("checksum error for %s: %v", it.Name, err))
				return
			}
			hashHex := hex.EncodeToString(hasher.Sum(nil))

			if _, err := file.Seek(0, io.SeekStart); err != nil {
				eng.transfers.notifyComplete(batchID, false, fmt.Sprintf("seek error for %s: %v", it.Name, err))
				return
			}

			sources = append(sources, BatchSendSource{
				FileID:   fmt.Sprintf("f-%d", i+1),
				FileName: it.Name,
				FileSize: it.Size,
				SHA256:   hashHex,
				Reader:   file,
			})
		}

		if eng.tsServer == nil {
			eng.transfers.notifyComplete(batchID, false, "tsnet server not ready")
			return
		}

		client := eng.tsServer.HTTPClient()
		sanitizedName := sanitizeHostname(eng.config.DeviceName)
		serverHostname := fmt.Sprintf("snowdrop-%s", sanitizedName)

		_ = eng.transfers.SendBatch(
			eng.ctx,
			client,
			peerIP,
			eng.config.Port,
			batchID,
			sources,
			serverHostname,
		)
	}()
}

// CancelAndroidTransfer cancels an ongoing transfer on Android
func CancelAndroidTransfer(transferID string) {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		eng.CancelTransfer(transferID)
	}
}

// ResolveAndroidApproval resolves an incoming transfer approval on Android
func ResolveAndroidApproval(transferID string, decision int) bool {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		return eng.ResolveApproval(transferID, decision)
	}
	return false
}

// GetAndroidTrustedPeersJSON returns trusted peers as a JSON string
func GetAndroidTrustedPeersJSON() string {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		return eng.GetTrustedPeersJSON()
	}
	return "[]"
}

// RevokeAndroidTrusted revokes a peer's trusted status on Android
func RevokeAndroidTrusted(nodeID string) bool {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		return eng.RevokeTrusted(nodeID)
	}
	return false
}

// SetAndroidApprovalConfig configures security approval preferences on Android
func SetAndroidApprovalConfig(requireApproval bool, autoAcceptTrusted bool) {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		eng.SetApprovalConfig(requireApproval, autoAcceptTrusted)
	}
}

// SignOutAndroid logs out the Android engine and requests a new login URL
func SignOutAndroid() bool {
	androidMu.Lock()
	eng := androidEngine
	androidMu.Unlock()

	if eng != nil {
		return eng.SignOut() == nil
	}
	return false
}
