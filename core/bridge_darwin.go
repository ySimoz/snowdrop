//go:build ignore

package main

/*
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

typedef void (*StatusCallback)(int status, const char* message);
typedef void (*AuthRequiredCallback)(const char* authURL);
typedef void (*PeersUpdatedCallback)(const char* peersJSON);
typedef void (*ProgressCallback)(const char* transferID, int64_t current, int64_t total);
typedef void (*TransferCompleteCallback)(const char* transferID, bool success, const char* errorMsg);

static void callStatusCb(StatusCallback cb, int status, const char* msg) {
    if (cb) cb(status, msg);
}
static void callAuthRequiredCb(AuthRequiredCallback cb, const char* url) {
    if (cb) cb(url);
}
static void callPeersUpdatedCb(PeersUpdatedCallback cb, const char* json) {
    if (cb) cb(json);
}
static void callProgressCb(ProgressCallback cb, const char* id, int64_t cur, int64_t total) {
    if (cb) cb(id, cur, total);
}
static void callTransferCompleteCb(TransferCompleteCallback cb, const char* id, bool ok, const char* err) {
    if (cb) cb(id, ok, err);
}
*/
import "C"
import (
	"sync"
	"unsafe"

	"github.com/username/snowdrop/core"
)

var (
	darwinMu           sync.Mutex
	activeEngine       *core.Engine
	cbStatus           C.StatusCallback
	cbAuthRequired     C.AuthRequiredCallback
	cbPeersUpdated     C.PeersUpdatedCallback
	cbProgress         C.ProgressCallback
	cbTransferComplete C.TransferCompleteCallback
)

//export RegisterCallbacks
func RegisterCallbacks(
	statusCb C.StatusCallback,
	authCb C.AuthRequiredCallback,
	peersCb C.PeersUpdatedCallback,
	progressCb C.ProgressCallback,
	completeCb C.TransferCompleteCallback,
) {
	darwinMu.Lock()
	defer darwinMu.Unlock()
	cbStatus = statusCb
	cbAuthRequired = authCb
	cbPeersUpdated = peersCb
	cbProgress = progressCb
	cbTransferComplete = completeCb
}

//export StartEngine
func StartEngine(dataDir *C.char, downloadDir *C.char, deviceName *C.char) C.int {
	darwinMu.Lock()
	if activeEngine != nil {
		darwinMu.Unlock()
		return 0
	}
	darwinMu.Unlock()

	dDir := C.GoString(dataDir)
	dlDir := C.GoString(downloadDir)
	dName := C.GoString(deviceName)

	cfg := &core.EngineConfig{
		DataDir:     dDir,
		DownloadDir: dlDir,
		DeviceName:  dName,
		OnStatusChange: func(status int, message string) {
			darwinMu.Lock()
			cb := cbStatus
			darwinMu.Unlock()
			if cb != nil {
				cMsg := C.CString(message)
				defer C.free(unsafe.Pointer(cMsg))
				C.callStatusCb(cb, C.int(status), cMsg)
			}
		},
		OnAuthRequired: func(authURL string) {
			darwinMu.Lock()
			cb := cbAuthRequired
			darwinMu.Unlock()
			if cb != nil {
				cURL := C.CString(authURL)
				defer C.free(unsafe.Pointer(cURL))
				C.callAuthRequiredCb(cb, cURL)
			}
		},
		OnPeersUpdated: func(peersJSON string) {
			darwinMu.Lock()
			cb := cbPeersUpdated
			darwinMu.Unlock()
			if cb != nil {
				cJSON := C.CString(peersJSON)
				defer C.free(unsafe.Pointer(cJSON))
				C.callPeersUpdatedCb(cb, cJSON)
			}
		},
		OnProgress: func(transferID string, bytesTransferred int64, totalBytes int64) {
			darwinMu.Lock()
			cb := cbProgress
			darwinMu.Unlock()
			if cb != nil {
				cID := C.CString(transferID)
				defer C.free(unsafe.Pointer(cID))
				C.callProgressCb(cb, cID, C.int64_t(bytesTransferred), C.int64_t(totalBytes))
			}
		},
		OnTransferComplete: func(transferID string, success bool, errorMsg string) {
			darwinMu.Lock()
			cb := cbTransferComplete
			darwinMu.Unlock()
			if cb != nil {
				cID := C.CString(transferID)
				defer C.free(unsafe.Pointer(cID))
				cErr := C.CString(errorMsg)
				defer C.free(unsafe.Pointer(cErr))
				C.callTransferCompleteCb(cb, cID, C.bool(success), cErr)
			}
		},
	}

	eng, err := core.NewEngine(cfg)
	if err != nil {
		return -1
	}

	if err := eng.Start(); err != nil {
		return -2
	}

	darwinMu.Lock()
	activeEngine = eng
	darwinMu.Unlock()
	return 0
}

//export StopEngine
func StopEngine() {
	darwinMu.Lock()
	eng := activeEngine
	activeEngine = nil
	darwinMu.Unlock()

	if eng != nil {
		eng.Stop()
	}
}

//export SendFile
func SendFile(peerIP *C.char, filePath *C.char, transferID *C.char) {
	pIP := C.GoString(peerIP)
	fPath := C.GoString(filePath)
	tID := C.GoString(transferID)

	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		go func() {
			_ = eng.SendFile(pIP, fPath, tID)
		}()
	}
}

//export CancelTransfer
func CancelTransfer(transferID *C.char) {
	tID := C.GoString(transferID)

	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		eng.CancelTransfer(tID)
	}
}

func main() {}
