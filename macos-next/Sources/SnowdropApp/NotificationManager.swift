import AppKit
import Foundation
import UserNotifications
import SnowdropCore

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private static let approvalCategoryIdentifier = "INCOMING_TRANSFER_APPROVAL"
    private weak var store: SnowdropStore?
    private var isConfigured = false

    func configure(store: SnowdropStore) {
        self.store = store

        store.onIncomingApproval = { [weak self] request in
            self?.postIncomingApproval(request)
        }
        store.onApprovalCleared = { [weak self] transferID in
            self?.clearApprovalNotification(id: transferID)
        }
        store.onTransferCompleted = { [weak self] transfer in
            self?.postTransferCompletion(transfer)
        }

        guard !isConfigured, Bundle.main.bundleIdentifier != nil else { return }
        isConfigured = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let acceptAction = UNNotificationAction(
            identifier: ApprovalDecision.acceptActionIdentifier,
            title: "Accept",
            options: []
        )
        let trustAction = UNNotificationAction(
            identifier: ApprovalDecision.trustActionIdentifier,
            title: "Always Trust",
            options: []
        )
        let declineAction = UNNotificationAction(
            identifier: ApprovalDecision.declineActionIdentifier,
            title: "Decline",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: Self.approvalCategoryIdentifier,
            actions: [acceptAction, trustAction, declineAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postIncomingApproval(_ request: IncomingApprovalRequest) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Incoming file transfer"
        content.body = "\(request.senderName) wants to send \(request.fileName) (\(request.formattedSize))"
        content.sound = .default
        content.categoryIdentifier = Self.approvalCategoryIdentifier
        content.userInfo = ["transferID": request.id]

        let req = UNNotificationRequest(identifier: request.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func clearApprovalNotification(id: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func postTransferCompletion(_ transfer: TransferItem) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = transfer.isSuccess ? "Transfer complete" : "Transfer failed"
        if transfer.isSuccess {
            content.body = transfer.direction == .incoming
                ? "Received \(transfer.fileName) from \(transfer.peerName)"
                : "Sent \(transfer.fileName) to \(transfer.peerName)"
        } else {
            content.body = "Failed to transfer \(transfer.fileName): \(transfer.errorMessage ?? "Unknown error")"
        }
        content.sound = .default

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let transferID = (response.notification.request.content.userInfo["transferID"] as? String)
            ?? response.notification.request.identifier

        await MainActor.run { [weak self] in
            guard let self, let store else { return }
            if let decision = ApprovalDecision(notificationActionIdentifier: actionID) {
                Task { await store.resolveApproval(id: transferID, decision: decision) }
            } else if actionID != UNNotificationDismissActionIdentifier {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
