import Foundation
import Testing
@testable import SnowdropCore

@Suite("BookmarkStore & download directory persistence")
struct BookmarkStoreTests {
    @MainActor
    @Test
    func saveRestoreMissingFolderFallbackAndClear() async throws {
        let suite = "com.snowdrop.bookmarks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-bm-\(UUID().uuidString)", isDirectory: true)
        let defaultDir = tempRoot.appendingPathComponent("Default", isDirectory: true)
        let customDir = tempRoot.appendingPathComponent("Custom", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BookmarkStore(userDefaults: defaults)
        #expect(await store.restoreDownloadDirectory(defaultURL: defaultDir) == defaultDir)

        await store.saveDownloadDirectory(customDir)
        let restored = await BookmarkStore(userDefaults: defaults).restoreDownloadDirectory(defaultURL: defaultDir)
        #expect(restored.resolvingSymlinksInPath().path == customDir.resolvingSymlinksInPath().path)

        // Deleted folder falls back to defaultURL
        try FileManager.default.removeItem(at: customDir)
        let fallback = await BookmarkStore(userDefaults: defaults).restoreDownloadDirectory(defaultURL: defaultDir)
        #expect(fallback == defaultDir)

        // Re-create and clear
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        await store.saveDownloadDirectory(customDir)
        store.clearCustomDownloadDirectory()
        #expect(await BookmarkStore(userDefaults: defaults).restoreDownloadDirectory(defaultURL: defaultDir) == defaultDir)
    }

    @MainActor
    @Test
    func snowdropStoreUpdatesResetsHandlesFailuresAndShutdown() async throws {
        let suite = "com.snowdrop.storebm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-custom-dl-\(UUID().uuidString)", isDirectory: true)
        let customDir = tempRoot.appendingPathComponent("Custom", isDirectory: true)
        let rejectedDir = tempRoot.appendingPathComponent("Rejected", isDirectory: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rejectedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let mock = MockSnowdropBackend()
        let store = SnowdropStore(backend: mock, userDefaults: defaults)
        await store.start()
        #expect(store.isDefaultDownloadDirectory == true)

        #expect(await store.updateDownloadDirectory(customDir) == true)
        #expect(store.isDefaultDownloadDirectory == false)
        #expect(store.downloadDirectory.path == customDir.path)
        #expect(await mock.lastDownloadDirectory?.path == customDir.path)

        // Backend rejection keeps previous folder & bookmark intact and surfaces error
        await mock.setDownloadDirectoryShouldSucceed(false)
        #expect(await store.updateDownloadDirectory(rejectedDir) == false)
        #expect(store.downloadDirectory.path == customDir.path)
        #expect(store.lastError == "Unable to update download folder")

        // Reset rejection preserves custom folder & bookmark
        #expect(await store.resetDownloadDirectory() == false)
        #expect(store.downloadDirectory.path == customDir.path)
        #expect(store.lastError == "Unable to reset download folder")

        // Reload restores custom directory on start()
        await mock.setDownloadDirectoryShouldSucceed(true)
        let reloaded = SnowdropStore(backend: mock, userDefaults: defaults)
        await reloaded.start()
        #expect(reloaded.downloadDirectory.resolvingSymlinksInPath().path == customDir.resolvingSymlinksInPath().path)

        // Successful reset clears persisted bookmark across subsequent reload
        #expect(await reloaded.resetDownloadDirectory() == true)
        #expect(reloaded.isDefaultDownloadDirectory == true)
        await reloaded.shutdown()

        let afterReset = SnowdropStore(backend: mock, userDefaults: defaults)
        await afterReset.start()
        #expect(afterReset.isDefaultDownloadDirectory == true)
        await afterReset.shutdown()
    }
}
