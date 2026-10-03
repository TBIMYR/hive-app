import SwiftUI

struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dir = NSHomeDirectory() + "/Development/"
    @State private var error: String?
    let onCreated: (String) -> Void

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("z. B. lu.04"))
            TextField("Verzeichnis", text: $dir)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Starten", action: start).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func start() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let d = (dir as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: d, isDirectory: &isDir), isDir.boolValue else {
            error = "Verzeichnis gibt es nicht: \(d)"
            return
        }
        if Tmux.hasSession(n) { error = "tmux-Session \(n) läuft schon"; return }
        if let e = Tmux.newSession(name: n, dir: d) { error = e; return }
        onCreated(n)
        dismiss()
    }
}
