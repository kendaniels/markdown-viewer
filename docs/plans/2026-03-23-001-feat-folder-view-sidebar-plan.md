---
title: "feat: Add folder view sidebar"
type: feat
status: active
date: 2026-03-23
---

# feat: Add folder view sidebar

A toggleable sidebar that shows other markdown files in the same folder as the currently opened file, with expandable subfolders that also contain markdown files.

## Acceptance Criteria

- [ ] Sidebar lists all `.md`, `.markdown`, and `.mdown` files in the same directory as the open file
- [ ] Subfolders containing markdown files (recursively, up to 10 levels) appear as expandable tree nodes
- [ ] Clicking a file in the sidebar loads it in the viewer
- [ ] Toolbar toggle button shows/hides the sidebar (keyboard shortcut: Cmd+Control+S via `NavigationSplitView` default)
- [ ] Currently open file is visually highlighted in the sidebar
- [ ] Sidebar tree stays rooted at the original parent directory when navigating into subfolders (introduce `sidebarRootURL` separate from `contentBaseURL`)
- [ ] Sidebar refreshes when a file from a different directory is opened (re-roots the tree)
- [ ] Sidebar visibility state persists across app launches via `UserDefaults`
- [ ] Directory enumeration happens on a background thread to avoid UI freezes on large directories
- [ ] Hidden files/directories (prefixed with `.`) are excluded
- [ ] Folders first, then files, both sorted alphabetically (case-insensitive)

## Context

### Architecture decisions

- **Layout:** Migrate `ContentView` from `VStack` to `NavigationSplitView` (macOS 13+ already required). This gives standard sidebar toggle behavior for free.
- **State model:** Introduce a new `SidebarModel` (`ObservableObject`) separate from `DocumentController` to own the file tree, expansion state, and sidebar root URL. It observes `DocumentController.contentBaseURL` changes.
- **`sidebarRootURL` vs `contentBaseURL`:** Critical distinction — `contentBaseURL` changes with every file open (used for resolving relative image paths in the WebView). `sidebarRootURL` only changes when a file outside the current tree is opened, keeping the sidebar stable during subfolder navigation.
- **File extensions:** Show `.md`, `.markdown`, `.mdown` — not `.txt`/`.plainText` (too noisy).
- **Live filesystem watching:** Not included in MVP. Sidebar refreshes only when a new file is opened. Can add FSEvents/DispatchSource later.

### Key files to modify

- `Sources/MarkdownViewerApp.swift` — Add `sidebarRootURL` to `DocumentController`, inject `SidebarModel`
- `Sources/ContentView.swift` — Restructure layout to `NavigationSplitView`, add sidebar view
- `Sources/WindowSizePersistence.swift` — Reference pattern for `UserDefaults` persistence

### New files

- `Sources/SidebarModel.swift` — File tree enumeration, expansion state, sidebar root tracking
- `Sources/SidebarView.swift` — SwiftUI sidebar view with `List` + `DisclosureGroup` for tree display

### Edge cases to handle

- Empty directories (no markdown files) — hide from tree
- Symlink cycle detection during recursive enumeration
- `contentBaseURL` becoming `nil` on file load error — show empty sidebar or retain previous tree
- Very large directories — background enumeration + loading indicator

## MVP

### SidebarModel.swift

```swift
import Foundation
import Combine

struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
}

class SidebarModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: "sidebarVisible") }
    }

    private var sidebarRootURL: URL?
    private let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    private let maxDepth = 10

    init() {
        self.isVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
    }

    func updateRoot(for fileURL: URL, contentBaseURL: URL?) {
        guard let baseURL = contentBaseURL else { return }

        // Only re-root if the new file is outside the current tree
        if let currentRoot = sidebarRootURL,
           fileURL.path.hasPrefix(currentRoot.path) {
            return
        }

        sidebarRootURL = baseURL
        enumerateAsync(directory: baseURL)
    }

    private func enumerateAsync(directory: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let nodes = self.buildTree(at: directory, depth: 0)
            DispatchQueue.main.async {
                self.rootNodes = nodes
            }
        }
    }

    private func buildTree(at url: URL, depth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for item in contents {
            // Skip symlinks to avoid cycles
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                continue
            }

            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                let children = buildTree(at: item, depth: depth + 1)
                if !children.isEmpty { // Only show folders that contain markdown
                    folders.append(FileNode(
                        url: item, name: item.lastPathComponent,
                        isDirectory: true, children: children
                    ))
                }
            } else if markdownExtensions.contains(item.pathExtension.lowercased()) {
                files.append(FileNode(
                    url: item, name: item.lastPathComponent,
                    isDirectory: false, children: nil
                ))
            }
        }

        return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
             + files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

### SidebarView.swift

```swift
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var documentController: DocumentController
    @ObservedObject var sidebarModel: SidebarModel

    var body: some View {
        List(selection: Binding(
            get: { documentController.fileURL },
            set: { url in
                if let url { documentController.loadDocument(from: url) }
            }
        )) {
            ForEach(sidebarModel.rootNodes) { node in
                if node.isDirectory {
                    FolderNode(node: node)
                } else {
                    FileRow(node: node)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct FolderNode: View {
    let node: FileNode

    var body: some View {
        DisclosureGroup {
            ForEach(node.children ?? []) { child in
                if child.isDirectory {
                    FolderNode(node: child)
                } else {
                    FileRow(node: child)
                }
            }
        } label: {
            Label(node.name, systemImage: "folder")
        }
    }
}

struct FileRow: View {
    let node: FileNode

    var body: some View {
        Label(node.name, systemImage: "doc.text")
            .tag(node.url)
    }
}
```

### ContentView.swift changes

```swift
// Wrap existing layout in NavigationSplitView
NavigationSplitView {
    SidebarView(sidebarModel: sidebarModel)
} detail: {
    // Existing VStack { toolbar; Divider; viewerArea }
}
```

## Sources

- Similar pattern: `Sources/WindowSizePersistence.swift` (UserDefaults persistence)
- Key file: `Sources/MarkdownViewerApp.swift:85` (`DocumentController.loadDocument` and `contentBaseURL`)
- Key file: `Sources/ContentView.swift` (layout restructure target)
