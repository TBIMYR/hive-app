import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: StateStore
    @Binding var selected: String?
    @State private var showNew = false

    // nach Projekt zusammengefasst (hive gruppiert nach Namensanfang, das ergab hier mehrfach „hive“)
    private var groups: [(key: String, label: String, sessions: [Session])] {
        var order: [String] = []
        var map: [String: [Session]] = [:]
        for s in store.sessions {
            let k = (s.project?.isEmpty == false ? s.project : nil) ?? s.group ?? s.name
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(s)
        }
        return order.map { k in
            let list = map[k]!.enumerated()
                .sorted { a, b in
                    let (pa, pb) = (a.element.isPm == true, b.element.isPm == true)
                    return pa != pb ? pa : a.offset < b.offset
                }
                .map(\.element)
            return (k, k, list)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("hive").font(.title2.bold())
                Spacer()
                Button("Neue Session") { showNew = true }
                    .disabled(Tmux.path == nil)
                    .help(Tmux.path == nil ? "tmux ist nicht installiert" : "claude -n in tmux starten")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("hive läuft nicht", systemImage: "hexagon", description: Text(error))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.key) { g in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(g.label.uppercased())
                                    .font(.caption.weight(.semibold)).tracking(0.8)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                    ForEach(g.sessions) { s in
                                        Tile(session: s, isSelected: s.name == selected)
                                            .onTapGesture { selected = s.name }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showNew) {
            NewSessionSheet { name in selected = name }
        }
    }
}

struct Tile: View {
    let session: Session
    let isSelected: Bool

    var body: some View {
        let st = Status(session)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(session.name).font(.system(.body, design: .monospaced).weight(.medium))
                if session.isPm == true {
                    Text("PM").font(.caption2.bold())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary).foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                StatusPill(status: st)
            }
            Text(st.why ?? session.task?.text ?? "–")
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(3)
            if let branch = session.branch, branch != "HEAD" {
                Text(branch).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.primary : (st.rank == 0 ? st.color : Color.secondary.opacity(0.25)),
                              lineWidth: isSelected || st.rank == 0 ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(st.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

struct StatusPill: View {
    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}
