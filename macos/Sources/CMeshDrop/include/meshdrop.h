#ifndef MESHDROP_H
#define MESHDROP_H

#include <stdint.h>
#include <stdbool.h>

typedef void (*StatusCallback)(int status, const char* message);
typedef void (*AuthRequiredCallback)(const char* authURL);
typedef void (*PeersUpdatedCallback)(const char* peersJSON);
typedef void (*ProgressCallback)(const char* transferID, int64_t current, int64_t total);
typedef void (*TransferCompleteCallback)(const char* transferID, bool success, const char* errorMsg);

void RegisterCallbacks(
    StatusCallback statusCb,
    AuthRequiredCallback authCb,
    PeersUpdatedCallback peersCb,
    ProgressCallback progressCb,
    TransferCompleteCallback completeCb
);

int StartEngine(const char* dataDir, const char* downloadDir, const char* deviceName);
void StopEngine(void);
void SendFile(const char* peerIP, const char* filePath, const char* transferID);
void CancelTransfer(const char* transferID);

#endif
