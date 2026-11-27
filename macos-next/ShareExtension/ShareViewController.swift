import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "Sending to Snowdrop…")
    private let spinner = NSProgressIndicator()
    private var timeoutTask: Task<Void, Never>?
    private var didStart = false
    private var didFinish = false

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 84))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(spinner)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20)
        ])

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        startHandoff()
    }

    private func startHandoff() {
        let providers = collectProviders()
        guard !providers.isEmpty else {
            finish()
            return
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.finish()
        }

        Task { [weak self] in
            guard let self else { return }
            let urls = await Self.resolveAllFileURLs(from: providers)
            let validURLs = Self.validatedFileURLs(from: urls)
            guard !validURLs.isEmpty else {
                self.showStatusAndFinish("No supported files to send")
                return
            }

            if let containerURL = ShareHandoffStore.defaultContainerURL() {
                let handoffID = await Task.detached(priority: .userInitiated) {
                    try? ShareHandoffStore.writeHandoff(fileURLs: validURLs, in: containerURL).id
                }.value

                if let handoffID {
                    guard !self.didFinish else { return }
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil

                    let targetURL = ShareHandoffStore.handoffURL(for: handoffID)
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    _ = try? await NSWorkspace.shared.open(targetURL, configuration: config)
                    self.finish()
                    return
                }
            }

            // Unsigned/ad-hoc builds cannot write to an App Group container under AMFI;
            // fall back to opening the security-scoped file URLs directly in Snowdrop.app.
            guard let appURL = Self.containingAppURL() else {
                self.showStatusAndFinish("Unable to send to Snowdrop")
                return
            }

            guard !self.didFinish else { return }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do {
                _ = try await NSWorkspace.shared.open(validURLs, withApplicationAt: appURL, configuration: config)
                self.finish()
            } catch {
                self.showStatusAndFinish("Unable to send to Snowdrop")
            }
        }
    }

    private func collectProviders() -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }
        return items.flatMap { $0.attachments ?? [] }
    }

    private func showStatusAndFinish(_ message: String) {
        statusLabel.stringValue = message
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        timeoutTask = nil
        spinner.stopAnimation(nil)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func containingAppURL() -> URL? {
        let candidate = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Snowdrop.app
        if candidate.pathExtension == "app" {
            return candidate
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.snowdrop.mac")
    }

    private static func validatedFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            let didStartScope = url.startAccessingSecurityScopedResource()
            defer {
                if didStartScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if case .success = FilePathValidator.validate(url) {
                return true
            }
            return false
        }
    }

    private static func resolveAllFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var resolved: [URL] = []
        for provider in providers {
            if let url = await resolveFileURL(from: provider) {
                resolved.append(url)
            }
        }
        return resolved
    }

    private static func resolveFileURL(from provider: NSItemProvider) async -> URL? {
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            typeIdentifier = UTType.fileURL.identifier
        } else {
            typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.item.identifier
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: extractURL(from: item))
            }
        }
    }

    nonisolated private static func extractURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let nsurl = item as? NSURL {
            return nsurl as URL
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }
            if let str = String(data: data, encoding: .utf8) {
                return URL(string: str) ?? URL(fileURLWithPath: str)
            }
        }
        if let str = item as? String {
            return URL(string: str) ?? URL(fileURLWithPath: str)
        }
        return nil
    }
}
