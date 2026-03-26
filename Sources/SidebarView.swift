import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var documentController: DocumentController
    @EnvironmentObject private var sidebarModel: SidebarModel

    var body: some View {
        Group {
            if sidebarModel.rootNodes.isEmpty {
                Text("Open a file to browse its folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
        }
    }

    private var fileList: some View {
        List(selection: Binding(
            get: { documentController.fileURL },
            set: { url in
                guard let url else { return }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                    documentController.loadDocument(from: url)
                }
            }
        )) {
            ForEach(sidebarModel.rootNodes) { node in
                FileNodeView(node: node)
            }
        }
        .listStyle(.sidebar)
    }
}

struct FileNodeView: View {
    let node: FileNode

    var body: some View {
        if node.isDirectory {
            FolderNodeView(node: node)
        } else {
            Label(node.name, systemImage: "doc.text")
                .tag(node.url)
        }
    }
}

struct FolderNodeView: View {
    let node: FileNode
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(node.children ?? []) { child in
                FileNodeView(node: child)
            }
        } label: {
            Label(node.name, systemImage: "folder")
                .onTapGesture {
                    isExpanded.toggle()
                }
        }
    }
}
