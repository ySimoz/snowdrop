import Foundation

public struct ShareHandoffManifest: Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let fileNames: [String]

    public init(id: UUID, createdAt: Date, fileNames: [String]) {
        self.id = id
        self.createdAt = createdAt
        self.fileNames = fileNames
    }
}

public enum ShareHandoffError: Error, Equatable, Sendable {
    case noValidFiles
    case invalidManifest
    case unsafeFileName(String)
}

public enum ShareHandoffStore {
    public static let defaultAppGroupSuffix = "com.snowdrop.mac.shared"
    private static let handoffFolderName = "Handoff"
    private static let filesFolderName = "files"
    private static let manifestFileName = "manifest.json"

    public static func resolvedAppGroupIdentifier(bundle: Bundle = .main) -> String {
        if let configured = bundle.object(forInfoDictionaryKey: "SnowdropAppGroupIdentifier") as? String {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("$(") {
                return trimmed
            }
        }
        return defaultAppGroupSuffix
    }

    public static func defaultContainerURL(appGroupID: String? = nil) -> URL? {
        let resolvedID = appGroupID ?? resolvedAppGroupIdentifier()
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolvedID)
    }

    public static func handoffURL(for id: UUID) -> URL {
        URL(string: "snowdrop://handoff?id=\(id.uuidString)")!
    }

    /// Parses only `snowdrop://handoff?id=<uuid>`; explicitly rejects legacy `snowdrop://send?path=...`.
    public static func handoffID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "snowdrop",
              url.host?.lowercased() == "handoff",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawID = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    public static func writeHandoff(fileURLs: [URL], in containerURL: URL) throws -> ShareHandoffManifest {
        let fm = FileManager.default
        let handoffID = UUID()
        let sessionDir = containerURL
            .appendingPathComponent(handoffFolderName, isDirectory: true)
            .appendingPathComponent(handoffID.uuidString, isDirectory: true)
        let filesDir = sessionDir.appendingPathComponent(filesFolderName, isDirectory: true)

        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)

        var copiedNames: [String] = []
        do {
            for rawURL in fileURLs {
                let didStartScope = rawURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartScope {
                        rawURL.stopAccessingSecurityScopedResource()
                    }
                }
                guard case .success(let resolvedURL) = FilePathValidator.validate(rawURL) else {
                    continue
                }
                let uniqueName = resolveUniqueFileName(in: filesDir, preferredName: resolvedURL.lastPathComponent)
                let destination = filesDir.appendingPathComponent(uniqueName, isDirectory: false)
                try fm.copyItem(at: resolvedURL, to: destination)
                copiedNames.append(uniqueName)
            }

            guard !copiedNames.isEmpty else {
                throw ShareHandoffError.noValidFiles
            }

            let manifest = ShareHandoffManifest(id: handoffID, createdAt: Date(), fileNames: copiedNames)
            let data = try JSONEncoder().encode(manifest)
            let manifestURL = sessionDir.appendingPathComponent(manifestFileName, isDirectory: false)
            try data.write(to: manifestURL, options: .atomic)
            return manifest
        } catch {
            try? fm.removeItem(at: sessionDir)
            throw error
        }
    }

    public static func consumeHandoff(id: UUID, in containerURL: URL) throws -> [URL] {
        let fm = FileManager.default
        let sessionDir = containerURL
            .appendingPathComponent(handoffFolderName, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let filesDir = sessionDir.appendingPathComponent(filesFolderName, isDirectory: true)
        let manifestURL = sessionDir.appendingPathComponent(manifestFileName, isDirectory: false)

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ShareHandoffManifest.self, from: data)
        guard manifest.id == id else {
            throw ShareHandoffError.invalidManifest
        }

        let resolvedFilesRoot = filesDir.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = resolvedFilesRoot.hasSuffix("/") ? resolvedFilesRoot : resolvedFilesRoot + "/"

        var resultURLs: [URL] = []
        for fileName in manifest.fileNames {
            guard isSafeSingleFileName(fileName) else {
                throw ShareHandoffError.unsafeFileName(fileName)
            }
            let candidate = filesDir.appendingPathComponent(fileName, isDirectory: false)
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedCandidate.path.hasPrefix(rootPrefix) else {
                throw ShareHandoffError.unsafeFileName(fileName)
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: resolvedCandidate.path, isDirectory: &isDir), !isDir.boolValue {
                resultURLs.append(resolvedCandidate)
            }
        }

        // Remove manifest so the handoff ID cannot be replayed; files stay until expired cleanup.
        try? fm.removeItem(at: manifestURL)
        return resultURLs
    }

    public static func cleanupExpiredHandoffs(
        in containerURL: URL,
        olderThan maxAge: TimeInterval = 86_400,
        now: Date = Date()
    ) {
        let fm = FileManager.default
        let handoffRoot = containerURL.appendingPathComponent(handoffFolderName, isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(
            at: handoffRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for dir in children {
            let manifestURL = dir.appendingPathComponent(manifestFileName, isDirectory: false)
            let timestamp: Date?
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(ShareHandoffManifest.self, from: data) {
                timestamp = manifest.createdAt
            } else {
                let values = try? dir.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                timestamp = values?.contentModificationDate ?? values?.creationDate
            }

            if let timestamp, now.timeIntervalSince(timestamp) > maxAge {
                try? fm.removeItem(at: dir)
            }
        }
    }

    private static func isSafeSingleFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            return false
        }
        return true
    }

    private static func sanitizeFileName(_ raw: String) -> String {
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            scalar.value >= 32 && scalar.value != 127
        }
        var cleaned = String(String.UnicodeScalarView(filteredScalars))
        cleaned = cleaned.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "file"
        }
        return cleaned
    }

    private static func resolveUniqueFileName(in directory: URL, preferredName: String) -> String {
        let clean = sanitizeFileName(preferredName)
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.appendingPathComponent(clean).path) {
            return clean
        }

        let ext = (clean as NSString).pathExtension
        let stem = (clean as NSString).deletingPathExtension
        for index in 1...10_000 {
            let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            if !fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
                return candidate
            }
        }
        return "\(stem)-\(UUID().uuidString.prefix(8))\(ext.isEmpty ? "" : ".\(ext)")"
    }
}
