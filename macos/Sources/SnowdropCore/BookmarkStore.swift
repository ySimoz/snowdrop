import Foundation

@MainActor
public final class BookmarkStore {
    private static let bookmarkKey = "SnowdropDownloadDirBookmark"
    private static let pathKey = "SnowdropDownloadDirPath"

    private let userDefaults: UserDefaults
    private var activeScopedURL: URL?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func restoreDownloadDirectory(defaultURL: URL) async -> URL {
        let bookmarkData = userDefaults.data(forKey: Self.bookmarkKey)
        let savedPath = userDefaults.string(forKey: Self.pathKey)

        if let bookmarkData {
            let resolvedOutcome = await Task.detached(priority: .utility) { () -> (url: URL, isStale: Bool, didStartScope: Bool)? in
                var isStale = false
                guard let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else {
                    return nil
                }

                // Activate security scope before probing existence under App Sandbox.
                let didStart = resolved.startAccessingSecurityScopedResource()
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) && isDir.boolValue
                guard exists else {
                    if didStart {
                        resolved.stopAccessingSecurityScopedResource()
                    }
                    return nil
                }
                return (resolved, isStale, didStart)
            }.value

            if let outcome = resolvedOutcome {
                stopAccessing()
                if outcome.didStartScope {
                    activeScopedURL = outcome.url
                }
                userDefaults.set(outcome.url.path, forKey: Self.pathKey)
                if outcome.isStale {
                    await persistBookmarkData(for: outcome.url)
                }
                return outcome.url
            }
        }

        if let savedPath, !savedPath.isEmpty {
            let exists = await Task.detached(priority: .utility) {
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDir) && isDir.boolValue
            }.value
            if exists {
                return URL(fileURLWithPath: savedPath, isDirectory: true)
            }
        }

        return defaultURL
    }

    public func saveDownloadDirectory(_ url: URL) async {
        activateScope(for: url)
        userDefaults.set(url.path, forKey: Self.pathKey)
        await persistBookmarkData(for: url)
    }

    public func clearCustomDownloadDirectory() {
        stopAccessing()
        userDefaults.removeObject(forKey: Self.bookmarkKey)
        userDefaults.removeObject(forKey: Self.pathKey)
    }

    public func stopAccessing() {
        if let activeScopedURL {
            activeScopedURL.stopAccessingSecurityScopedResource()
            self.activeScopedURL = nil
        }
    }

    private func activateScope(for url: URL) {
        guard activeScopedURL != url else { return }
        stopAccessing()
        if url.startAccessingSecurityScopedResource() {
            activeScopedURL = url
        }
    }

    private func persistBookmarkData(for url: URL) async {
        let data = await Task.detached(priority: .utility) {
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }.value

        if let data {
            userDefaults.set(data, forKey: Self.bookmarkKey)
        } else {
            // Avoid keeping a stale bookmark pointing at a different folder than pathKey.
            userDefaults.removeObject(forKey: Self.bookmarkKey)
        }
    }
}
