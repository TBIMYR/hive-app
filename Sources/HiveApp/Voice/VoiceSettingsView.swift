import AppKit
import SwiftUI

extension Notification.Name {
    /// the ElevenLabs key was saved or removed in Settings
    static let voiceKeyChanged = Notification.Name("hiveVoiceKeyChanged")
}

/// Settings → Voice.
struct VoiceSettingsView: View {
    @AppStorage(VoiceSettings.enabledKey) private var enabled = false
    @AppStorage(VoiceSettings.triggerKey) private var trigger = VoiceSettings.Trigger.rightOption.rawValue
    @AppStorage(VoiceSettings.announceKey) private var announce = true
    @AppStorage(VoiceSettings.followUpKey) private var followUp = true
    @AppStorage(VoiceSettings.announceDoneKey) private var announceDone = true
    @AppStorage(VoiceSettings.outputKey) private var output = VoiceSettings.Output.eleven.rawValue
    @AppStorage(VoiceSettings.elevenVoiceKey) private var voiceID = ""
    @AppStorage(VoiceSettings.stabilityKey) private var stability = 0.5
    @AppStorage(VoiceSettings.modelKey) private var model = "haiku"
    @AppStorage(VoiceSettings.userNameKey) private var userName = ""
    @AppStorage(VoiceSettings.speedKey) private var speed = 0.92
    @State private var newKey = ""
    @State private var hasKey = VoiceKeychain.read() != nil

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Text("Talk to Hive")
                Text("Hold the key, speak, let go. Hive answers aloud and knows every session; it passes things on only after your yes. Speech is recognised on this Mac, the answers come from Claude with your normal login.")
            }
            TextField(text: $userName, prompt: Text("Optional")) {
                Text("Your name")
                Text("Hive calls you by it now and then. Stays in this Mac's settings.")
            }
            Picker(selection: $trigger) {
                ForEach(VoiceSettings.Trigger.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            } label: {
                Text("Push-to-talk key")
                Text("Right ⌥ needs Input Monitoring for Hive (System Settings → Privacy & Security). Pressed together with another key it does nothing, so ⌥-characters still work.")
            }
            if trigger == VoiceSettings.Trigger.rightOption.rawValue {
                Button("Open Input Monitoring Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
            Toggle(isOn: $followUp) {
                Text("Just answer, without the key")
                Text("After Hive spoke, the microphone stays open for a few seconds; a pause ends what you said. Starting a conversation still takes the key.")
            }
            Toggle(isOn: $announce) {
                Text("Speak up when a session needs me")
                Text("Hive says who waits and for what. A short answer then goes to that session after a pause in which the key stops it.")
            }
            Toggle(isOn: $announceDone) {
                Text("Say when a session is done")
                Text("When its task line turns done, or after at least two minutes of work. Not for the session open in front of you.")
            }
        }
        Section("Voice") {
            Picker("Voice", selection: $output) {
                ForEach(VoiceSettings.Output.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            LabeledContent {
                HStack(spacing: 8) {
                    if hasKey {
                        Text("Saved in the keychain").foregroundStyle(.secondary)
                        Button("Remove") { VoiceKeychain.remove(); keyChanged() }
                    } else {
                        SecureField("Paste the key", text: $newKey).frame(width: 180)
                        Button("Save") { VoiceKeychain.save(newKey); newKey = ""; keyChanged() }
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } label: {
                Text("ElevenLabs key")
                Text("Only \"Text to Speech\" access is needed. Without a key Hive uses the macOS voice.")
            }
            TextField(text: $voiceID, prompt: Text("Sarah")) {
                Text("ElevenLabs voice ID")
                Text("Empty = Sarah. Voices from the voice library need a paid ElevenLabs plan.")
            }
            Slider(value: $stability, in: 0.1...0.8) {
                Text("Livelier ↔ steadier")
            }
            Slider(value: $speed, in: 0.7...1.15) {
                Text("Slower ↔ faster")
            }
        }
        Section {
            Picker(selection: $model) {
                Text("Haiku (fastest)").tag("haiku")
                Text("Sonnet").tag("sonnet")
            } label: {
                Text("Model")
                Text("Session names are spoken as words (lu.01 → \"Lumen eins\"); own names go into ~/.config/hive-voice/names.json, e.g. {\"lu\": \"Luna\"}.")
            }
        }
    }

    private func keyChanged() {
        hasKey = VoiceKeychain.read() != nil
        NotificationCenter.default.post(name: .voiceKeyChanged, object: nil)
    }
}
