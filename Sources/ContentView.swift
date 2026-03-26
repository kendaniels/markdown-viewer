import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var documentController: DocumentController
    @EnvironmentObject private var sidebarModel: SidebarModel
    @State private var isDropTargeted = false
    @State private var pathText: String = ""
    @State private var pathError: Bool = false
    @FocusState private var isPathFieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            if sidebarModel.isVisible {
                SidebarView()
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

                Divider()
            }

            VStack(spacing: 0) {
                toolbar

                Divider()

                viewerArea

                if documentController.fileURL != nil && documentController.errorMessage == nil {
                    Divider()
                    statusBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowSizeTrackingView())
        .onReceive(NotificationCenter.default.publisher(for: .focusPathBar)) { _ in
            isPathFieldFocused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                withAnimation {
                    sidebarModel.isVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")

            Button {
                documentController.openDocument()
            } label: {
                Image(systemName: "folder")
            }
            .help("Open Markdown")

            HStack(spacing: 0) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .opacity(pathError ? 1 : 0)
                    .help("File not found")

                TextField("No file selected", text: $pathText)
                    .font(.system(size: 12))
                    .textFieldStyle(.roundedBorder)
                    .focused($isPathFieldFocused)
                    .onSubmit {
                        submitPath()
                    }
                    .onChange(of: pathText) { _ in
                        pathError = false
                    }
                    .onReceive(documentController.$fileURL) { url in
                        pathText = url?.path ?? ""
                        pathError = false
                    }
                    .onExitCommand {
                        pathText = documentController.fileURL?.path ?? ""
                        pathError = false
                    }
                    .onTapGesture {
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    }
            }

            if documentController.fileURL != nil {
                Button {
                    documentController.openInEditor()
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Open in Editor")
            }
        }
        .padding(12)
    }

    private func submitPath() {
        let trimmed = pathText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let resolved: String
        if expanded.hasPrefix("/") {
            resolved = expanded
        } else if let base = documentController.fileURL?.deletingLastPathComponent().path {
            resolved = (base as NSString).appendingPathComponent(expanded)
        } else {
            resolved = (NSHomeDirectory() as NSString).appendingPathComponent(expanded)
        }

        let url = URL(fileURLWithPath: resolved)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            sidebarModel.setRootDirectory(url)
            pathError = false
        } else if !documentController.tryLoadDocument(from: url) {
            pathError = true
        }
    }

    private var viewerArea: some View {
        ZStack {
            if let errorMessage = documentController.errorMessage {
                ErrorStateView(message: errorMessage)
            } else if documentController.fileURL == nil {
                EmptyStateView()
            } else {
                MarkdownTextView(
                    html: documentController.renderedHTML,
                    baseURL: documentController.contentBaseURL,
                    isDropTargeted: $isDropTargeted,
                    onDropFile: { url in
                        documentController.loadDocument(from: url)
                    }
                )
            }

            if isDropTargeted {
                DropOverlayView()
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            documentController.handleDroppedItems(providers)
        }
    }

    private var statusBar: some View {
        HStack {
            Spacer()
            if let date = documentController.lastModifiedDate {
                Text("Modified: \(date.formatted(date: .abbreviated, time: .standard))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EmptyStateView: View {
    var body: some View {
        Text("Drag and drop a markdown file here")
            .font(.system(size: 32, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DropOverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
    }
}
