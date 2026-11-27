import Foundation
import Testing
@testable import SnowdropCore

@Suite("FilePathValidator security & path validation")
struct FilePathValidatorTests {
    @Test
    func acceptsRegularFileAndResolvesSymlink() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("report.pdf")
        try Data("pdf".utf8).write(to: target)

        let link = dir.appendingPathComponent("alias.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let directResult = FilePathValidator.validate(target)
        #expect(try directResult.get() == target.resolvingSymlinksInPath().standardizedFileURL)

        let linkResult = FilePathValidator.validate(link)
        #expect(try linkResult.get() == target.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test
    func rejectsDirectoriesHiddenFilesAndMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(FilePathValidator.validate(dir) == .failure(.isDirectory))

        let hidden = dir.appendingPathComponent(".secret")
        try Data("hidden".utf8).write(to: hidden)
        #expect(FilePathValidator.validate(hidden) == .failure(.hiddenFile))

        let missing = dir.appendingPathComponent("does-not-exist.txt")
        #expect(FilePathValidator.validate(missing) == .failure(.notFound))
    }

    @Test
    func rejectsSensitiveLocationsAndSymlinkEscape() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snowdrop-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let etcHosts = URL(fileURLWithPath: "/etc/hosts")
        #expect(FilePathValidator.validate(etcHosts) == .failure(.sensitiveLocation))

        let sshKey = URL(fileURLWithPath: "/Users/example/.ssh/id_rsa")
        #expect(FilePathValidator.validate(sshKey) == .failure(.sensitiveLocation))

        let snowdropState = URL(fileURLWithPath: "/Users/example/Library/Application Support/Snowdrop/tailscaled.state")
        #expect(FilePathValidator.validate(snowdropState) == .failure(.sensitiveLocation))

        let symlinkToEtc = dir.appendingPathComponent("hosts-link.txt")
        try FileManager.default.createSymbolicLink(at: symlinkToEtc, withDestinationURL: etcHosts)
        #expect(FilePathValidator.validate(symlinkToEtc) == .failure(.sensitiveLocation))
    }
}
