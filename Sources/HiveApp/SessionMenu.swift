import SwiftUI
import HiveCore

/// Right-click menu for card, row, and tile. The store comes in as a parameter,
/// so the menu doesn't depend on the context menu's environment.
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
        // control only works via tmux, so only for sessions running in hive
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
