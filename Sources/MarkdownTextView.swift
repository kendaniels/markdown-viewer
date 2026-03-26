import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkdownTextView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var isDropTargeted: Bool
    let onDropFile: (URL) -> Void

    func makeNSView(context: Context) -> DropEnabledWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let webView = DropEnabledWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.dropDelegate = context.coordinator

        return webView
    }

    func updateNSView(_ webView: DropEnabledWebView, context: Context) {
        context.coordinator.isDropTargeted = $isDropTargeted
        context.coordinator.onDropFile = onDropFile

        let previousHTML = context.coordinator.lastLoadedHTML
        let previousBaseURL = context.coordinator.lastLoadedBaseURL

        guard html != previousHTML || baseURL != previousBaseURL else { return }

        context.coordinator.lastLoadedHTML = html
        context.coordinator.lastLoadedBaseURL = baseURL

        if previousBaseURL == baseURL && previousHTML != nil {
            // Same base URL — swap body content and preserve scroll position
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            webView.evaluateJavaScript("""
                (function() {
                    var scrollY = window.scrollY;
                    document.documentElement.innerHTML = `\(escaped)`;
                    window.scrollTo(0, scrollY);
                })();
                """)
        } else {
            // Different base URL or first load — full reload required
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDropTargeted: $isDropTargeted, onDropFile: onDropFile)
    }
}

extension MarkdownTextView {
    final class Coordinator: NSObject, DropEnabledWebViewDelegate {
        var isDropTargeted: Binding<Bool>
        var onDropFile: (URL) -> Void
        var lastLoadedHTML: String?
        var lastLoadedBaseURL: URL?

        init(isDropTargeted: Binding<Bool>, onDropFile: @escaping (URL) -> Void) {
            self.isDropTargeted = isDropTargeted
            self.onDropFile = onDropFile
        }

        func dropEnabledWebView(_ webView: DropEnabledWebView, isTargeted: Bool) {
            isDropTargeted.wrappedValue = isTargeted
        }

        func dropEnabledWebView(_ webView: DropEnabledWebView, didReceiveFileURL url: URL) {
            onDropFile(url)
        }
    }
}

protocol DropEnabledWebViewDelegate: AnyObject {
    func dropEnabledWebView(_ webView: DropEnabledWebView, isTargeted: Bool)
    func dropEnabledWebView(_ webView: DropEnabledWebView, didReceiveFileURL url: URL)
}

final class DropEnabledWebView: WKWebView {
    weak var dropDelegate: DropEnabledWebViewDelegate?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard extractDroppedFileURL(from: sender) != nil else {
            dropDelegate?.dropEnabledWebView(self, isTargeted: false)
            return []
        }

        dropDelegate?.dropEnabledWebView(self, isTargeted: true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard extractDroppedFileURL(from: sender) != nil else {
            dropDelegate?.dropEnabledWebView(self, isTargeted: false)
            return []
        }

        dropDelegate?.dropEnabledWebView(self, isTargeted: true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropDelegate?.dropEnabledWebView(self, isTargeted: false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = extractDroppedFileURL(from: sender) else {
            dropDelegate?.dropEnabledWebView(self, isTargeted: false)
            return false
        }

        dropDelegate?.dropEnabledWebView(self, isTargeted: false)
        dropDelegate?.dropEnabledWebView(self, didReceiveFileURL: url)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropDelegate?.dropEnabledWebView(self, isTargeted: false)
    }

    private func extractDroppedFileURL(from draggingInfo: NSDraggingInfo) -> URL? {
        let pasteboard = draggingInfo.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }
}
