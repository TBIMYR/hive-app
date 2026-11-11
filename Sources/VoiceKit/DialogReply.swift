import Foundation
import HiveCore

/// A spoken answer to a choice dialog on a session's screen: the option number, the option's text,
/// or for an approval "ja" / "immer" / "nein". Other words go into a question's "Type something." line as the
/// user's own answer; an approval has none, so there they are refused. The result is what Hive's answer buttons
/// send, so it goes through the same checks (`Tmux.answer`).
public enum DialogReply {
    public static func answer(_ reply: String, in dialog: ScreenDialog) -> ScreenDialog.Answer? {
        let t = reply.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let n = Int(t) { return dialog.options.first { $0.number == n }.map { .option($0.label) } }
        if let exact = dialog.option(labeled: t) { return .option(exact.label) }
        let words = Set(t.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let choice: ScreenDialog.PermissionChoice?
        if !words.isDisjoint(with: ["nein", "no", "nicht", "ablehnen", "stopp"]) { choice = .deny }
        else if !words.isDisjoint(with: ["immer", "always", "dauerhaft"]) { choice = .alwaysAllow }
        else if !words.isDisjoint(with: ["ja", "yes", "erlaub", "erlauben", "erlaubt", "ok", "okay", "mach", "go"]) { choice = .allow }
        else { choice = nil }
        if let choice, dialog.permission(choice) != nil { return .permission(choice) }
        let own = reply.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !own.isEmpty, dialog.pick(.text(own)) != nil else { return nil }
        return .text(own)
    }

    /// The options for the model, e.g. "1. Yes / 2. Yes, and don't ask again … / 3. No".
    public static func describe(_ dialog: ScreenDialog) -> String {
        dialog.options.map { "\($0.number). \($0.label)" }.joined(separator: " / ")
    }
}
