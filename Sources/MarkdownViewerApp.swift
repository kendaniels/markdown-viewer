import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var documentController = DocumentController.shared
    @StateObject private var sidebarModel = SidebarModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentController)
                .environmentObject(sidebarModel)
                .frame(minWidth: 720, minHeight: 480)
                .onOpenURL { url in
                    documentController.loadDocument(from: url)
                }
                .onAppear {
                    sidebarModel.bind(to: documentController)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    documentController.openDocument()
                }
                .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        let launchURLs = CommandLine.arguments
            .dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        open(urls: launchURLs)
    }

    private func open(urls: [URL]) {
        guard let url = urls.first else {
            return
        }

        DispatchQueue.main.async {
            DocumentController.shared.loadDocument(from: url)
        }
    }
}

final class DocumentController: ObservableObject {
    static let shared = DocumentController()

    @Published private(set) var fileURL: URL?
    @Published private(set) var contentBaseURL: URL?
    @Published private(set) var renderedHTML = MarkdownRenderer.placeholderHTML
    @Published private(set) var errorMessage: String?

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
        do {
            let markdown = try String(contentsOf: url)
            let renderedHTML = try MarkdownRenderer.render(markdown)
            fileURL = url
            contentBaseURL = url.deletingLastPathComponent()
            self.renderedHTML = renderedHTML
            errorMessage = nil
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
