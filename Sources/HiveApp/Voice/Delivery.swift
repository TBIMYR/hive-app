import Foundation
import HiveCore
import VoiceKit

/// Why a message from the voice or the broadcast field did not reach its session.
enum DeliveryFailure: Equatable {
    case unknownSession, notInHive, dialogChanged, noMatchingOption, typingFailed
}

extension StateStore {
    /// The running session of that name, else any (an offline one can't be typed into, which `deliver` reports).
    func session(named name: String) -> Session? {
        displaySessions.first { $0.name == name && ($0.alive || tmux($0) != nil) }
            ?? displaySessions.first { $0.name == name }
    }

    /// Like a card: a visible choice dialog gets the option (answer buttons), otherwise the text is typed (reply field).
    func deliver(_ text: String, to name: String) async -> DeliveryFailure? {
        guard let s = session(named: name) else { return .unknownSession }
        guard tmux(s) != nil else { return .notInHive }
        if let dialog = await dialog(s) {
            guard let a = DialogReply.answer(text, in: dialog) else { return .noMatchingOption }
            return await answer(a, known: dialog.options.map(\.label), to: s).map { _ in .dialogChanged }
        }
        return await reply(text, to: s).map { _ in .typingFailed }
    }
}
