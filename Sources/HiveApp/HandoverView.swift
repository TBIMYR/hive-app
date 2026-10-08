import MarkdownUI
import SwiftUI

/// Read a session's handover, like the sidebar in the dashboard.
/// Renders the Markdown (without frontmatter, which `Handover.body` cuts off) with MarkdownUI in the `.hive` theme.
struct HandoverView: View {
    @EnvironmentObject private var store: StateStore
    let name: String
    @State private var text: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            Group {
                if let text {
                    Markdown(text).markdownTheme(.hive)
                } else if loaded {
                    Text("No handover.").foregroundStyle(Hive.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32).padding(.vertical, 26)
            .textSelection(.enabled)
        }
        .scrollIndicators(.never)
        .task(id: name) {
            loaded = false
            text = await store.handover(name)
            loaded = true
        }
    }
}

/// Calm reading typography for handover: 14 pt body text, generous line and paragraph spacing,
/// colors from `Hive` (dynamic light/dark).
extension Theme {
    static let hive = Theme()
        .text {
            ForegroundColor(Hive.ink)
            FontSize(15)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Hive.soft)
        }
        .strong { FontWeight(.semibold) }
        .link { ForegroundColor(Hive.shell) }
        .heading1 { c in
            c.label
                .markdownMargin(top: 0, bottom: 18)
                .markdownTextStyle {
                    FontSize(20)
                    FontWeight(.bold)
                }
        }
        .heading2 { c in
            c.label
                .markdownMargin(top: 30, bottom: 12)
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.semibold)
                }
        }
        .heading3 { c in
            c.label
                .markdownMargin(top: 22, bottom: 8)
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.semibold)
                }
        }
        .heading4 { c in
            c.label
                .markdownMargin(top: 16, bottom: 6)
                .markdownTextStyle {
                    FontSize(13.5)
                    FontWeight(.semibold)
                    ForegroundColor(Hive.ink2)
                }
        }
        .paragraph { c in
            c.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.65))
                .markdownMargin(top: 0, bottom: 16)
        }
        .list { c in
            c.label.markdownMargin(top: 0, bottom: 14)
        }
        .listItem { c in
            c.label.markdownMargin(top: 10)
        }
        .bulletedListMarker { _ in
            Text("•")
                .foregroundStyle(Hive.muted)
                .relativeFrame(minWidth: .em(1.2), alignment: .trailing)
        }
        .numberedListMarker { c in
            Text("\(c.itemNumber).")
                .monospacedDigit()
                .foregroundStyle(Hive.muted)
                .relativeFrame(minWidth: .em(1.6), alignment: .trailing)
        }
        .blockquote { c in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Hive.hair2)
                    .frame(width: 3)
                c.label
                    .markdownTextStyle { ForegroundColor(Hive.ink2) }
                    .padding(.leading, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 10)
        }
        .codeBlock { c in
            ScrollView(.horizontal) {
                c.label
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                    }
                    .padding(12)
            }
            .scrollIndicators(.never)
            .background(Hive.soft)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Hive.hair, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 0, bottom: 12)
        }
        .table { c in
            c.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Hive.hair))
                .markdownTableBackgroundStyle(.alternatingRows(Color.clear, Hive.soft))
                .markdownMargin(top: 0, bottom: 12)
        }
        .tableCell { c in
            c.label
                .markdownTextStyle {
                    if c.row == 0 { FontWeight(.semibold) }
                    FontSize(13)
                }
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
        }
        .thematicBreak {
            Rectangle()
                .fill(Hive.hair)
                .frame(height: 1)
                .markdownMargin(top: 14, bottom: 14)
        }
}
