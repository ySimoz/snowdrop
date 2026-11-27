import Foundation

@MainActor
public final class SecurityScopedAccessTracker {
    private var retainCounts: [URL: Int] = [:]
    private var startedURLs: Set<URL> = []

    public init() {}

    public func retain(_ url: URL) {
        let count = retainCounts[url, default: 0]
        if count == 0 && url.startAccessingSecurityScopedResource() {
            startedURLs.insert(url)
        }
        retainCounts[url] = count + 1
    }

    public func release(_ url: URL) {
        guard let count = retainCounts[url] else { return }
        if count <= 1 {
            retainCounts.removeValue(forKey: url)
            if startedURLs.remove(url) != nil {
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            retainCounts[url] = count - 1
        }
    }

    public func releaseAll() {
        for url in startedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        startedURLs.removeAll()
        retainCounts.removeAll()
    }
}
