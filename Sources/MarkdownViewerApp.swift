import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let debugLogURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("markdown-viewer-debug.log")
private func debugLog(_ message: String) {
    let line = "\(Date()): \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: debugLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: debugLogURL)
        }
    }
}

extension Notification.Name {
    static let focusPathBar = Notification.Name("focusPathBar")
}

/// Stores a URL for the first window to pick up at launch.
enum PendingOpen {
    static var launchURL: URL?
}

// Associate a DocumentController directly with an NSWindow.
private var documentControllerKey: UInt8 = 0

extension NSWindow {
    var documentController: DocumentController? {
        get { objc_getAssociatedObject(self, &documentControllerKey) as? DocumentController }
        set { objc_setAssociatedObject(self, &documentControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedObject private var focusedDocumentController: DocumentController?

    var body: some Scene {
        WindowGroup {
            WindowContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Focus Path Bar") {
                    NotificationCenter.default.post(name: .focusPathBar, object: nil)
                }
                .keyboardShortcut("l")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    focusedDocumentController?.openDocument()
                }
                .keyboardShortcut("o")

                Button("Open in Editor") {
                    focusedDocumentController?.openInEditor()
                }
                .keyboardShortcut("e")
                .disabled(focusedDocumentController?.fileURL == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Each window gets its own DocumentController and SidebarModel.
private struct WindowContentView: View {
    @StateObject private var documentController = DocumentController()
    @StateObject private var sidebarModel = SidebarModel()

    var body: some View {
        ContentView()
            .environmentObject(documentController)
            .environmentObject(sidebarModel)
            .focusedObject(documentController)
            .onAppear {
                sidebarModel.bind(to: documentController)
                // Claim any launch-time URL (e.g. Finder double-click that launched the app)
                if let url = PendingOpen.launchURL {
                    PendingOpen.launchURL = nil
                    documentController.loadDocument(from: url)
                }
            }
            .background(WindowBinder(documentController: documentController))
    }
}

/// Attaches the DocumentController to the hosting NSWindow via associated objects.
private struct WindowBinder: NSViewRepresentable {
    let documentController: DocumentController

    func makeNSView(context: Context) -> NSView {
        let view = BinderView()
        view.documentController = documentController
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private class BinderView: NSView {
        var documentController: DocumentController?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.documentController = documentController
            debugLog("[Binder] window \(window?.windowNumber ?? -1) -> DC \(documentController?.instanceID ?? "nil")")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasHandledLaunchFiles = false
    /// Prevents duplicate processing when macOS calls multiple delegate methods for the same file.
    private var lastHandledURL: URL?

    /// Prevent macOS from creating an extra untitled window on launch or reactivation.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// Disable window state restoration to prevent restoring old windows on launch.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        open(urls: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only handle CLI arguments if no file was already opened via AppDelegate open methods
        // (Finder double-click triggers both, so skip CLI args in that case)
        guard !hasHandledLaunchFiles else { return }

        let launchURLs = CommandLine.arguments
            .dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        open(urls: launchURLs)
    }

    private func open(urls: [URL]) {
        guard let url = urls.first else { return }

        // Dedup: macOS may call multiple delegate methods for the same file open event.
        // Ignore duplicates within the same run loop cycle.
        guard url != lastHandledURL else { return }
        lastHandledURL = url
        DispatchQueue.main.async { self.lastHandledURL = nil }

        hasHandledLaunchFiles = true
        DispatchQueue.main.async {
            let windows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            debugLog("[AppDelegate] open \(url.lastPathComponent)")

            // Reuse an empty window (no file loaded yet), otherwise create a new one.
            // Never load into a window that already has a document open.
            if let emptyWindow = windows.first(where: { $0.documentController?.fileURL == nil }) {
                debugLog("[AppDelegate] reusing empty window \(emptyWindow.windowNumber)")
                emptyWindow.documentController?.loadDocument(from: url)
                emptyWindow.makeKeyAndOrderFront(nil)
            } else {
                debugLog("[AppDelegate] creating new window for \(url.lastPathComponent)")
                PendingOpen.launchURL = url
                NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
            }
        }
    }
}

final class DocumentController: ObservableObject {
    let instanceID = UUID().uuidString.prefix(6)

    @Published private(set) var fileURL: URL?
    @Published private(set) var contentBaseURL: URL?
    @Published private(set) var renderedHTML = MarkdownRenderer.placeholderHTML
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastModifiedDate: Date?

    private var refreshTimer: DispatchSourceTimer?

    deinit {
        refreshTimer?.cancel()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedContentTypes
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            loadDocument(from: url)
        }
    }

    func loadDocument(from url: URL) {
        let caller = Thread.callStackSymbols.prefix(6).joined(separator: "\n  ")
        debugLog("[DC \(instanceID)] loadDocument called: \(url.lastPathComponent)\n  \(caller)")
        do {
            let markdown = try String(contentsOf: url)
            let renderedHTML = try MarkdownRenderer.render(markdown)
            fileURL = url
            contentBaseURL = url.deletingLastPathComponent()
            self.renderedHTML = renderedHTML
            errorMessage = nil
            startFileWatcher()
        } catch {
            fileURL = url
            contentBaseURL = nil
            errorMessage = "Unable to open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
            guard let self, let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                self.loadDocument(from: url)
            }
        }

        return true
    }

    /// Attempts to load a document without mutating state on failure.
    /// Returns true if the document was loaded successfully.
    @discardableResult
    func tryLoadDocument(from url: URL) -> Bool {
        debugLog("[DC \(instanceID)] tryLoadDocument called: \(url.lastPathComponent)")
        do {
            let markdown = try String(contentsOf: url)
            let html = try MarkdownRenderer.render(markdown)
            fileURL = url
            contentBaseURL = url.deletingLastPathComponent()
            renderedHTML = html
            errorMessage = nil
            startFileWatcher()
            return true
        } catch {
            return false
        }
    }

    func openInEditor() {
        guard let fileURL else { return }
        let bundleID = UserDefaults.standard.string(forKey: "defaultEditorBundleID") ?? "com.apple.TextEdit"
        guard let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        NSWorkspace.shared.open([fileURL], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - File Watcher

    private func startFileWatcher() {
        refreshTimer?.cancel()
        guard let url = fileURL else { return }

        lastModifiedDate = Self.modificationDate(for: url)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkFileForChanges(url: url)
        }
        timer.resume()
        refreshTimer = timer
    }

    private static func modificationDate(for url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func checkFileForChanges(url: URL) {
        guard let newDate = Self.modificationDate(for: url) else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshTimer?.cancel()
                self?.refreshTimer = nil
            }
            return
        }
        guard newDate != lastModifiedDate else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastModifiedDate = newDate
            do {
                let markdown = try String(contentsOf: url)
                let html = try MarkdownRenderer.render(markdown)
                self.renderedHTML = html
                self.errorMessage = nil
            } catch {
                // Transient read failure — keep existing content, retry next tick
            }
        }
    }

    private var supportedContentTypes: [UTType] {
        [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown"),
            .plainText,
            .text,
        ].compactMap { $0 }
    }
}
