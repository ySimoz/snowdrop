import Cocoa
import Social
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: NSViewController {
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments, !attachments.isEmpty else {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        var handled = false
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { item, _ in
                    var fileURL: URL?
                    if let url = item as? URL {
                        fileURL = url
                    } else if let str = item as? String {
                        fileURL = URL(fileURLWithPath: str)
                    }

                    if let fileURL = fileURL {
                        let pathEncoded = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let schemeURL = URL(string: "snowdrop://send?path=\(pathEncoded)") {
                            NSWorkspace.shared.open(schemeURL)
                        }
                    }

                    DispatchQueue.main.async {
                        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    }
                }
                break
            }
        }

        if !handled {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
