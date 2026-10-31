import Cocoa
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "Sending to Snowdrop...")
    private let spinner = NSProgressIndicator()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))

        let iconView = NSImageView()
        let extBundle = Bundle(for: ShareViewController.self)
        let loadedIcon = extBundle.image(forResource: "AppIcon")
            ?? (extBundle.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) })
            ?? NSImage(named: "AppIcon")
        iconView.image = loadedIcon ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(spinner)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),

            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18)
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        processSharedFiles()
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.spinner.stopAnimation(nil)
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func processSharedFiles() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments, !attachments.isEmpty else {
            finish()
            return
        }

        // Safety fallback timer to guarantee Finder dismisses even if handoff fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.finish()
        }

        for provider in attachments {
            resolveURL(from: provider) { [weak self] fileURL in
                guard let self = self, let fileURL = fileURL else {
                    self?.finish()
                    return
                }
                self.stageAndOpen(fileURL: fileURL)
            }
            break
        }
    }

    private func resolveURL(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        if provider.canLoadObject(ofClass: NSURL.self) {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL {
                    completion(url)
                    return
                } else if let nsurl = object as? NSURL {
                    completion(nsurl as URL)
                    return
                }
                self.fallbackResolve(from: provider, completion: completion)
            }
        } else {
            fallbackResolve(from: provider, completion: completion)
        }
    }

    private func fallbackResolve(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let typeIdentifier = provider.registeredTypeIdentifiers.first { id in
            id == UTType.fileURL.identifier || id == "public.file-url"
        } ?? provider.registeredTypeIdentifiers.first ?? UTType.item.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            var fileURL: URL?
            if let url = item as? URL {
                fileURL = url
            } else if let nsurl = item as? NSURL {
                fileURL = nsurl as URL
            } else if let data = item as? Data {
                if let url = URL(dataRepresentation: data, relativeTo: nil) {
                    fileURL = url
                } else if let str = String(data: data, encoding: .utf8) {
                    fileURL = URL(string: str) ?? URL(fileURLWithPath: str)
                }
            } else if let str = item as? String {
                fileURL = URL(string: str) ?? URL(fileURLWithPath: str)
            }
            completion(fileURL)
        }
    }

    private func stageAndOpen(fileURL: URL) {
        let path = fileURL.path
        guard let pathEncoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let schemeURL = URL(string: "snowdrop://send?path=\(pathEncoded)") else {
            finish()
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open(schemeURL, configuration: config) { [weak self] _, _ in
            self?.finish()
        }
    }
}
