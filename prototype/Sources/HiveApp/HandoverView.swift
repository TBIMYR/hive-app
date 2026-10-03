import SwiftUI

/// Handover einer Session lesen, wie die Seitenleiste im Dashboard.
/// Einfaches Markdown: Überschriften, Aufzählungen (auch eingerückt), Absätze mit Inline-Formatierung.
struct HandoverView: View {
    @EnvironmentObject private var store: StateStore
    let name: String
    @State private var text: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let text {
                    ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, b in row(b) }
                } else if loaded {
                    Text("Kein Handover vorhanden.").foregroundStyle(Hive.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.vertical, 18)
            .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .task(id: name) {
            loaded = false
            text = await store.handover(name)
            loaded = true
        }
    }

    private enum Block { case h(Int, String), bullet(Int, String), para(String), gap }

    private static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = (line.count - line.drop { $0 == " " }.count) / 2
            if trimmed.isEmpty {
                if case .gap = out.last {} else if !out.isEmpty { out.append(.gap) }
            } else if trimmed.hasPrefix("### ") { out.append(.h(3, String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") { out.append(.h(2, String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") { out.append(.h(1, String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                out.append(.bullet(indent, String(trimmed.dropFirst(2))))
            } else { out.append(.para(trimmed)) }
        }
        return out
    }

    @ViewBuilder
    private func row(_ b: Block) -> some View {
        switch b {
        case .h(1, let t): Text(inline(t)).font(.system(size: 17, weight: .bold)).padding(.bottom, 4)
        case .h(2, let t): Text(inline(t)).font(.system(size: 14, weight: .semibold)).padding(.top, 10)
        case .h(_, let t): Text(inline(t)).font(.system(size: 13, weight: .semibold)).padding(.top, 6)
        case .bullet(let level, let t):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(Hive.muted)
                Text(inline(t)).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13)).padding(.leading, CGFloat(level) * 16)
        case .para(let t): Text(inline(t)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        case .gap: Color.clear.frame(height: 4)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}
