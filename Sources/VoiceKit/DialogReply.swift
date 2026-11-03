import Foundation
import HiveCore

/// A spoken answer to a choice dialog on a session's screen: the option number, the option's text,
/// or for an approval "ja" / "immer" / "nein". Text is never typed into a dialog.
public enum DialogReply {
    public static func pick(_ reply: String, in dialog: ScreenDialog) -> ScreenDialog.Option? {
        let t = reply.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let n = Int(t) { return dialog.options.first { $0.number == n } }
        if let exact = dialog.option(labeled: t) { return exact }
        let words = Set(t.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let choice: ScreenDialog.PermissionChoice?
        if !words.isDisjoint(with: ["nein", "no", "nicht", "ablehnen", "stopp"]) { choice = .deny }
        else if !words.isDisjoint(with: ["immer", "always", "dauerhaft"]) { choice = .alwaysAllow }
        else if !words.isDisjoint(with: ["ja", "yes", "erlaub", "erlauben", "erlaubt", "ok", "okay", "mach", "go"]) { choice = .allow }
        else { choice = nil }
        return choice.flatMap(dialog.permission)
    }

    /// The options for the model, e.g. "1. Yes / 2. Yes, and don't ask again … / 3. No".
    public static func describe(_ dialog: ScreenDialog) -> String {
        dialog.options.map { "\($0.number). \($0.label)" }.joined(separator: " / ")
    }
}
