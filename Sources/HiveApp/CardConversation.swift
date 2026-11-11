import SwiftUI
import HiveCore

/// The conversation in a full card (terminal hidden): the user's last message as a bubble on the right, below it
/// everything the session wrote since, set for reading and folded after about eight lines; while it works, its
/// last steps.
struct CardConversation: View {
    let session: Session
    let working: Bool
    let now: Date
    @State private var open = false
    @State private var height: CGFloat = 0

    private static let folded: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let you = session.lastUser {
                Text(QuestionReader.md(you.text))
                    .font(.system(size: 13)).foregroundStyle(Hive.ink2)
                    .lineLimit(3)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Hive.well))
                    .padding(.leading, 40)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let answer = session.answer {
                let long = height > Self.folded + 20
                let shut = long && !open
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(AnswerText.blocks(answer.text).enumerated()), id: \.offset) { _, b in block(b) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .frame(maxHeight: shut ? Self.folded : nil, alignment: .top)
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        if shut { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 36) }
                    }
                }
                if long {
                    Button(open ? "Show less" : "Show all") { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
                        .buttonStyle(.link).font(.system(size: 12, weight: .medium))
                }
            }
            if working, !session.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: step.pending ? "gearshape" : "checkmark")
                                .font(.system(size: 11, weight: .medium)).frame(width: 14)
                            Text(step.text).foregroundStyle(Hive.ink2).fixedSize()
                            if let d = step.detail { CodeChip(text: d) }
                            if step.pending { Text(dur(step.at, now: now)).fixedSize() }
                        }
                        .lineLimit(1)
                    }
                }
                .font(.system(size: 12.5)).foregroundStyle(Hive.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: session.lastUser?.at) { open = false }
    }

    @ViewBuilder private func block(_ b: AnswerText.Block) -> some View {
        switch b {
        case .heading(let h):
            Text(QuestionReader.md(h)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Hive.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let p):
            Text(QuestionReader.md(p)).font(.system(size: 14)).foregroundStyle(Hive.ink2).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        case .item(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).font(.hiveMono(12)).foregroundStyle(Hive.muted).frame(minWidth: 14, alignment: .trailing)
                Text(QuestionReader.md(text)).font(.system(size: 14)).foregroundStyle(Hive.ink2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .code(let c):
            Text(c).font(.hiveMono(12)).foregroundStyle(Hive.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Hive.well))
        }
    }
}
