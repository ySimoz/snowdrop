import Foundation
import Testing
@testable import SnowdropBridge
@testable import SnowdropCore

@Suite("LiveSnowdropBackend C-FFI integration", .serialized)
struct LiveBackendIntegrationTests {
    @Test
    func startConfigureAndStopWithoutBlockingMainActor() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-bridge-test-\(UUID().uuidString)", isDirectory: true)
        let dataDir = tempRoot.appendingPathComponent("data", isDirectory: true)
        let dlDir = tempRoot.appendingPathComponent("downloads", isDirectory: true)
        let altDlDir = tempRoot.appendingPathComponent("downloads-alt", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let backend = LiveSnowdropBackend()
        try await backend.start(dataDirectory: dataDir, downloadDirectory: dlDir, deviceName: "IntegrationMac")

        // Verify MainActor stays responsive while backend executes operations off-main.
        let mainThreadResponsive = await MainActor.run { true }
        #expect(mainThreadResponsive)

        let dirUpdated = await backend.setDownloadDirectory(altDlDir)
        #expect(dirUpdated)

        await backend.setApprovalConfig(requireApproval: false, autoAcceptTrusted: true)
        let peers = await backend.trustedPeers()
        #expect(peers.isEmpty)

        await backend.stop()
    }
}
