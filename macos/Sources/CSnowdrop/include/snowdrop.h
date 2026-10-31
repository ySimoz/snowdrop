#ifndef SNOWDROP_H
#define SNOWDROP_H

#include <stdint.h>
#include <stdbool.h>

typedef void (*StatusCallback)(int status, const char* message);
typedef void (*AuthRequiredCallback)(const char* authURL);
typedef void (*PeersUpdatedCallback)(const char* peersJSON);
typedef void (*ProgressCallback)(const char* transferID, int64_t current, int64_t total);
typedef void (*TransferCompleteCallback)(const char* transferID, bool success, const char* errorMsg);
typedef void (*ApprovalCallback)(const char* transferID, const char* nodeID, const char* senderName, const char* fileName, int64_t fileSize);
typedef void (*BatchProgressCallback)(const char* batchID, int fileIndex, int totalFiles, const char* fileName, int64_t fileCur, int64_t fileTotal, int64_t batchCur, int64_t batchTotal);

void RegisterCallbacks(
    StatusCallback statusCb,
    AuthRequiredCallback authCb,
    PeersUpdatedCallback peersCb,
    ProgressCallback progressCb,
    TransferCompleteCallback completeCb
);

void RegisterApprovalCallback(ApprovalCallback cb);
void RegisterBatchProgressCallback(BatchProgressCallback cb);

int StartEngine(const char* dataDir, const char* downloadDir, const char* deviceName);
void StopEngine(void);
void SendFile(const char* peerIP, const char* filePath, const char* transferID);
void SendBatch(const char* peerIP, const char* batchID, const char* filesJSON);
void CancelTransfer(const char* transferID);

bool ResolveTransferApproval(const char* transferID, int decision);
char* GetTrustedPeers(void);
bool RevokeTrusted(const char* nodeID);
void SetApprovalConfig(bool requireApproval, bool autoAcceptTrusted);
bool SnowdropSignOut(void);

#endif
