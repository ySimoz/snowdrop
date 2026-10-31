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
typedef void (*ApprovalCallback)(const char* transferID, const char* nodeID, const char* senderName, const char* fileName, int64_t fileSize);
typedef void (*BatchProgressCallback)(const char* batchID, int fileIndex, int totalFiles, const char* fileName, int64_t fileCur, int64_t fileTotal, int64_t batchCur, int64_t batchTotal);

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
static void callApprovalCb(ApprovalCallback cb, const char* id, const char* node, const char* sender, const char* file, int64_t size) {
    if (cb) cb(id, node, sender, file, size);
}
static void callBatchProgressCb(BatchProgressCallback cb, const char* id, int idx, int total, const char* name, int64_t fCur, int64_t fTotal, int64_t bCur, int64_t bTotal) {
    if (cb) cb(id, idx, total, name, fCur, fTotal, bCur, bTotal);
}
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"os"
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
	cbApproval         C.ApprovalCallback
	cbBatchProgress    C.BatchProgressCallback
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

//export RegisterApprovalCallback
func RegisterApprovalCallback(approvalCb C.ApprovalCallback) {
	darwinMu.Lock()
	defer darwinMu.Unlock()
	cbApproval = approvalCb
}

//export RegisterBatchProgressCallback
func RegisterBatchProgressCallback(batchProgressCb C.BatchProgressCallback) {
	darwinMu.Lock()
	defer darwinMu.Unlock()
	cbBatchProgress = batchProgressCb
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
		RequireApproval:   true,
		AutoAcceptTrusted: true,
		OnIncomingApproval: func(transferID string, senderNodeID string, senderName string, fileName string, sizeBytes int64) {
			darwinMu.Lock()
			cb := cbApproval
			darwinMu.Unlock()
			if cb != nil {
				cID := C.CString(transferID)
				defer C.free(unsafe.Pointer(cID))
				cNode := C.CString(senderNodeID)
				defer C.free(unsafe.Pointer(cNode))
				cSender := C.CString(senderName)
				defer C.free(unsafe.Pointer(cSender))
				cFile := C.CString(fileName)
				defer C.free(unsafe.Pointer(cFile))
				C.callApprovalCb(cb, cID, cNode, cSender, cFile, C.int64_t(sizeBytes))
			}
		},
		OnBatchProgress: func(batchID string, fileIndex int, totalFiles int, fileName string, fileBytes int64, fileTotal int64, batchBytes int64, batchTotal int64) {
			darwinMu.Lock()
			cb := cbBatchProgress
			darwinMu.Unlock()
			if cb != nil {
				cID := C.CString(batchID)
				defer C.free(unsafe.Pointer(cID))
				cName := C.CString(fileName)
				defer C.free(unsafe.Pointer(cName))
				C.callBatchProgressCb(cb, cID, C.int(fileIndex), C.int(totalFiles), cName, C.int64_t(fileBytes), C.int64_t(fileTotal), C.int64_t(batchBytes), C.int64_t(batchTotal))
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

type darwinBatchItem struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Size int64  `json:"size"`
}

//export SendBatch
func SendBatch(peerIP *C.char, batchID *C.char, filesJSON *C.char) {
	pIP := C.GoString(peerIP)
	bID := C.GoString(batchID)
	fJSON := C.GoString(filesJSON)

	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		go func() {
			var items []darwinBatchItem
			if err := json.Unmarshal([]byte(fJSON), &items); err != nil {
				eng.CancelTransfer(bID)
				return
			}

			var sources []core.BatchSendSource
			for i, it := range items {
				size := it.Size
				if size <= 0 {
					if fi, err := os.Stat(it.Path); err == nil {
						size = fi.Size()
					}
				}
				sources = append(sources, core.BatchSendSource{
					FileID:   fmt.Sprintf("f-%d", i+1),
					FileName: it.Name,
					FileSize: size,
					FilePath: it.Path,
				})
			}

			_ = eng.SendBatch(pIP, bID, sources)
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

//export ResolveTransferApproval
func ResolveTransferApproval(transferID *C.char, decision C.int) C.bool {
	tID := C.GoString(transferID)

	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		return C.bool(eng.ResolveApproval(tID, int(decision)))
	}
	return false
}

//export GetTrustedPeers
func GetTrustedPeers() *C.char {
	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		return C.CString(eng.GetTrustedPeersJSON())
	}
	return C.CString("[]")
}

//export RevokeTrusted
func RevokeTrusted(nodeID *C.char) C.bool {
	nID := C.GoString(nodeID)

	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		return C.bool(eng.RevokeTrusted(nID))
	}
	return false
}

//export SetApprovalConfig
func SetApprovalConfig(requireApproval C.bool, autoAcceptTrusted C.bool) {
	darwinMu.Lock()
	eng := activeEngine
	darwinMu.Unlock()

	if eng != nil {
		eng.SetApprovalConfig(bool(requireApproval), bool(autoAcceptTrusted))
	}
}

func main() {}
