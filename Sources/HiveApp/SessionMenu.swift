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
    }
}
