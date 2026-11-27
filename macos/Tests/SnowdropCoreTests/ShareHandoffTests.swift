import Foundation
import Testing
@testable import SnowdropCore

@Suite("ShareHandoff multi-file & CWE-22 safety")
struct ShareHandoffTests {
    @Test
    func multiFileHandoffRoundTripAndReplayPrevention() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-handoff-\(UUID().uuidString)", isDirectory: true)
        let sourceDir = tempRoot.appendingPathComponent("src", isDirectory: true)
        let containerDir = tempRoot.appendingPathComponent("container", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileA = sourceDir.appendingPathComponent("photo.jpg")
        let fileB = sourceDir.appendingPathComponent("notes.txt")
        let hidden = sourceDir.appendingPathComponent(".env")
        try Data("img".utf8).write(to: fileA)
        try Data("notes".utf8).write(to: fileB)
        try Data("secret".utf8).write(to: hidden)

        let manifest = try ShareHandoffStore.writeHandoff(fileURLs: [fileA, fileB, hidden], in: containerDir)
        #expect(manifest.fileNames == ["photo.jpg", "notes.txt"])

        let consumed = try ShareHandoffStore.consumeHandoff(id: manifest.id, in: containerDir)
        #expect(consumed.count == 2)
        #expect(Set(consumed.map(\.lastPathComponent)) == Set(["photo.jpg", "notes.txt"]))
        #expect(try Data(contentsOf: consumed[0]) == Data("img".utf8) || Data(contentsOf: consumed[0]) == Data("notes".utf8))

        // Replay blocked because manifest.json was consumed
        #expect(throws: (any Error).self) {
            try ShareHandoffStore.consumeHandoff(id: manifest.id, in: containerDir)
        }
    }

    @Test
    func handoffURLParsingRejectsLegacySendScheme() {
        let id = UUID()
        let validURL = ShareHandoffStore.handoffURL(for: id)
        #expect(ShareHandoffStore.handoffID(from: validURL) == id)

        let legacyURL = URL(string: "snowdrop://send?path=/etc/passwd")!
        #expect(ShareHandoffStore.handoffID(from: legacyURL) == nil)

        let invalidUUID = URL(string: "snowdrop://handoff?id=not-a-uuid")!
        #expect(ShareHandoffStore.handoffID(from: invalidUUID) == nil)
    }

    @Test
    func tamperedManifestTraversalIsRejected() throws {
        let containerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-cwe22-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerDir) }

        let id = UUID()
        let sessionDir = containerDir
            .appendingPathComponent("Handoff", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        let filesDir = sessionDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let evilManifest = ShareHandoffManifest(id: id, createdAt: Date(), fileNames: ["../secret.txt"])
        let data = try JSONEncoder().encode(evilManifest)
        try data.write(to: sessionDir.appendingPathComponent("manifest.json"))

        #expect(throws: ShareHandoffError.unsafeFileName("../secret.txt")) {
            try ShareHandoffStore.consumeHandoff(id: id, in: containerDir)
        }
    }

    @Test
    func symlinkEscapeDuplicateBasenamesNoValidFilesAndMissingManifestCleanup() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-edge-\(UUID().uuidString)", isDirectory: true)
        let dir1 = tempRoot.appendingPathComponent("d1", isDirectory: true)
        let dir2 = tempRoot.appendingPathComponent("d2", isDirectory: true)
        let containerDir = tempRoot.appendingPathComponent("container", isDirectory: true)
        let outsideFile = tempRoot.appendingPathComponent("outside.txt")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideFile)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Duplicate basenames from different folders receive collision-safe names
        let dupA = dir1.appendingPathComponent("photo.jpg")
        let dupB = dir2.appendingPathComponent("photo.jpg")
        try Data("A".utf8).write(to: dupA)
        try Data("B".utf8).write(to: dupB)
        let dupManifest = try ShareHandoffStore.writeHandoff(fileURLs: [dupA, dupB], in: containerDir)
        #expect(dupManifest.fileNames == ["photo.jpg", "photo (1).jpg"])

        // No valid files throws .noValidFiles
        let hidden = dir1.appendingPathComponent(".dot")
        try Data("x".utf8).write(to: hidden)
        #expect(throws: ShareHandoffError.noValidFiles) {
            try ShareHandoffStore.writeHandoff(fileURLs: [hidden, dir1], in: containerDir)
        }

        // Symlink inside files/ pointing outside files/ is rejected by containment check
        let symID = UUID()
        let symSession = containerDir
            .appendingPathComponent("Handoff", isDirectory: true)
            .appendingPathComponent(symID.uuidString, isDirectory: true)
        let symFiles = symSession.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: symFiles, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symFiles.appendingPathComponent("escape.txt"),
            withDestinationURL: outsideFile
        )
        let symManifest = ShareHandoffManifest(id: symID, createdAt: Date(), fileNames: ["escape.txt"])
        try JSONEncoder().encode(symManifest).write(to: symSession.appendingPathComponent("manifest.json"))
        #expect(throws: ShareHandoffError.unsafeFileName("escape.txt")) {
            try ShareHandoffStore.consumeHandoff(id: symID, in: containerDir)
        }

        // Expired cleanup works when manifest.json was already removed (directory mtime fallback)
        let noManifestID = UUID()
        let noManifestDir = containerDir
            .appendingPathComponent("Handoff", isDirectory: true)
            .appendingPathComponent(noManifestID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: noManifestDir, withIntermediateDirectories: true)
        let oldDate = Date(timeIntervalSinceNow: -100_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: noManifestDir.path)
        ShareHandoffStore.cleanupExpiredHandoffs(in: containerDir, olderThan: 86_400)
        #expect(FileManager.default.fileExists(atPath: noManifestDir.path) == false)
    }

    @Test
    func cleanupExpiredHandoffsRemovesStaleAndKeepsFresh() throws {
        let containerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerDir) }

        let handoffRoot = containerDir.appendingPathComponent("Handoff", isDirectory: true)
        let staleID = UUID()
        let freshID = UUID()
        let staleDir = handoffRoot.appendingPathComponent(staleID.uuidString, isDirectory: true)
        let freshDir = handoffRoot.appendingPathComponent(freshID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staleDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshDir, withIntermediateDirectories: true)

        let now = Date()
        let staleManifest = ShareHandoffManifest(id: staleID, createdAt: now.addingTimeInterval(-90_000), fileNames: [])
        let freshManifest = ShareHandoffManifest(id: freshID, createdAt: now.addingTimeInterval(-60), fileNames: [])
        try JSONEncoder().encode(staleManifest).write(to: staleDir.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(freshManifest).write(to: freshDir.appendingPathComponent("manifest.json"))

        ShareHandoffStore.cleanupExpiredHandoffs(in: containerDir, olderThan: 86_400, now: now)
        #expect(FileManager.default.fileExists(atPath: staleDir.path) == false)
        #expect(FileManager.default.fileExists(atPath: freshDir.path) == true)
    }
}
