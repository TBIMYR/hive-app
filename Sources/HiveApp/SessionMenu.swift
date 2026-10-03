import SwiftUI
import HiveCore

/// Rechtsklick-Menü für Karte, Zeile, Kachel und Pin. Der Store kommt als Parameter,
/// damit das Menü nicht vom Environment des Kontextmenüs abhängt.
struct SessionMenu: View {
    @ObservedObject var store: StateStore
    let session: Session

    var body: some View {
        if store.isPinned(session.name) {
            Button("Unpin") { store.unpin(session.name) }
        } else {
            Button("Pin") { store.pin(session.name) }
        }
        if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == session.groupKey }) {
            Button("Start \(next) in the same project") {
                store.newPreset = NewSessionPreset(name: next, dir: session.cwd)
            }
        }
    }
}
