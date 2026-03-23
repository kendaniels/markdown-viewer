import Combine
import Foundation

struct FileNode: Identifiable, Hashable, Equatable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url
            && lhs.name == rhs.name
            && lhs.isDirectory == rhs.isDirectory
            && lhs.children == rhs.children
    }
}

final class SidebarModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var isVisible = false

    private var sidebarRootURL: URL?
    private let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    private let maxDepth = 10
    private var cancellable: AnyCancellable?

    // File-system watching via polling
    private var pollSource: DispatchSourceTimer?

    init() {}

    deinit {
        stopWatching()
    }

    func bind(to documentController: DocumentController) {
        cancellable = documentController.$contentBaseURL
            .sink { [weak self] baseURL in
                self?.handleDirectoryChange(baseURL)
            }
    }

    private func handleDirectoryChange(_ newBaseURL: URL?) {
        guard let newBaseURL else { return }

        // If we have a root and the new file is inside it, keep the current tree
        if let root = sidebarRootURL,
           newBaseURL.path.hasPrefix(root.path) {
            return
        }

        // New file is outside the current tree — re-root
        sidebarRootURL = newBaseURL
        enumerateAsync(directory: newBaseURL)
    }

    private func enumerateAsync(directory: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let nodes = self.buildTree(at: directory, depth: 0)
            DispatchQueue.main.async {
                self.rootNodes = nodes
                // Auto-hide if the opened file is the only markdown file with no subfolders
                let fileCount = nodes.filter { !$0.isDirectory }.count
                let folderCount = nodes.filter { $0.isDirectory }.count
                if fileCount <= 1, folderCount == 0 {
                    self.isVisible = false
                } else {
                    self.isVisible = true
                }
                self.startPolling()
            }
        }
    }

    // MARK: – File-system watching (polling)

    private func stopWatching() {
        pollSource?.cancel()
        pollSource = nil
    }

    private func startPolling() {
        stopWatching()
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + 1, repeating: 1.0)
        source.setEventHandler { [weak self] in
            self?.checkForChanges()
        }
        source.resume()
        pollSource = source
    }

    private func checkForChanges() {
        guard let root = sidebarRootURL else { return }
        let nodes = buildTree(at: root, depth: 0)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard nodes != self.rootNodes else { return }
            self.rootNodes = nodes
            let fileCount = nodes.filter { !$0.isDirectory }.count
            let folderCount = nodes.filter { $0.isDirectory }.count
            if fileCount <= 1, folderCount == 0 {
                self.isVisible = false
            } else {
                self.isVisible = true
            }
        }
    }

    private func buildTree(at url: URL, depth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            // Skip symlinks to avoid cycles
            if resourceValues?.isSymbolicLink == true {
                continue
            }

            let isDir = resourceValues?.isDirectory ?? false

            if isDir {
                let children = buildTree(at: item, depth: depth + 1)
                if !children.isEmpty {
                    folders.append(FileNode(
                        id: item, url: item, name: item.lastPathComponent,
                        isDirectory: true, children: children
                    ))
                }
            } else if markdownExtensions.contains(item.pathExtension.lowercased()) {
                files.append(FileNode(
                    id: item, url: item, name: item.lastPathComponent,
                    isDirectory: false, children: nil
                ))
            }
        }

        return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            + files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
