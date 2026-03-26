import AppKit
import SwiftUI

struct EditorOption: Identifiable, Hashable {
    let id: String  // bundle identifier
    let name: String

    static let builtIn: [EditorOption] = [
        EditorOption(id: "com.apple.TextEdit", name: "TextEdit"),
        EditorOption(id: "com.microsoft.VSCode", name: "Visual Studio Code"),
        EditorOption(id: "com.sublimetext.4", name: "Sublime Text"),
        EditorOption(id: "com.panic.Nova", name: "Nova"),
        EditorOption(id: "com.barebones.bbedit", name: "BBEdit"),
        EditorOption(id: "dev.zed.Zed", name: "Zed"),
        EditorOption(id: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    static var installed: [EditorOption] {
        builtIn.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }
}

struct SettingsView: View {
    @AppStorage("defaultEditorBundleID") private var editorBundleID = "com.apple.TextEdit"

    var body: some View {
        Form {
            Picker("Default Editor", selection: $editorBundleID) {
                ForEach(EditorOption.installed) { editor in
                    Text(editor.name).tag(editor.id)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(20)
        .frame(width: 350)
    }
}
