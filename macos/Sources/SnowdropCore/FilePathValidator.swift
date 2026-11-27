import Foundation

public enum FileValidationFailure: Error, Equatable, Sendable {
    case notFound
    case isDirectory
    case hiddenFile
    case sensitiveLocation
}

public enum FilePathValidator {
    private static let blockedExactPrefixes: [String] = [
        "/etc/",
        "/private/etc/",
        "/var/db/",
        "/private/var/db/",
        "/var/root/",
        "/private/var/root/",
        "/var/log/",
        "/private/var/log/",
        "/var/run/",
        "/private/var/run/"
    ]

    private static let blockedSubstrings: [String] = [
        "/.ssh/",
        "/.aws/",
        "/.gnupg/",
        "/library/keychains/",
        "/library/cookies/",
        "/library/application support/snowdrop/"
    ]

    public static func validate(_ url: URL) -> Result<URL, FileValidationFailure> {
        guard url.isFileURL else {
            return .failure(.notFound)
        }

        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        if url.lastPathComponent.hasPrefix(".") || resolved.lastPathComponent.hasPrefix(".") {
            return .failure(.hiddenFile)
        }

        let lowerPath = resolved.path.lowercased()
        if isSensitivePath(lowerPath) {
            return .failure(.sensitiveLocation)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) else {
            return .failure(.notFound)
        }
        if isDir.boolValue {
            return .failure(.isDirectory)
        }

        return .success(resolved)
    }

    private static func isSensitivePath(_ lowerPath: String) -> Bool {
        for prefix in blockedExactPrefixes where lowerPath.hasPrefix(prefix) {
            return true
        }
        for fragment in blockedSubstrings where lowerPath.contains(fragment) {
            return true
        }
        return false
    }
}
