import SwiftUI
import HiveCore

/// Rechtsklick-Menü für Karte, Zeile und Kachel. Der Store kommt als Parameter,
/// damit das Menü nicht vom Environment des Kontextmenüs abhängt.
struct SessionMenu: View {
    @ObservedObject var store: StateStore
    let session: Session

    var body: some View {
        Button(store.isFavorite(session.name) ? "Remove from Favorites" : "Favorite") {
            store.toggleFavorite(session.name)
        }
        if let next = SessionNaming.nextName(in: store.sessions.filter { $0.groupKey == session.groupKey }) {
            Button("Start \(next) in the same project") {
                store.newPreset = NewSessionPreset(name: next, dir: session.cwd)
            }
        }
        Divider()
        // Steuern geht nur über tmux, also nur für Sessions, die in hive laufen
        let inHive = store.tmux(session) != nil
        let help = inHive ? "" : "Only for sessions running in Hive"
        Group {
            Button("Write Handover") { store.writeHandover(session) }
            Button("Restart…") { store.requestClose(session, restart: true) }
            Button("Close…") { store.requestClose(session, restart: false) }
        }
        .disabled(!inHive)
        .help(help)
    }
}
