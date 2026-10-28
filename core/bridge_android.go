package core

import (
	"crypto/sha256"
	"encoding/hex"
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
