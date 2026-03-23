import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var documentController: DocumentController
    @EnvironmentObject private var sidebarModel: SidebarModel
    @State private var isDropTargeted = false

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowSizeTrackingView())
    }

    private var toolbar: some View {
        HStack {
            Button("Open Markdown") {
                documentController.openDocument()
            }

            Button {
                withAnimation {
                    sidebarModel.isVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")

            Spacer()

            Text(documentController.fileURL?.path ?? "No file selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
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
