import RepCoachCore
import SwiftUI

struct SettingsView: View {
    @Environment(VoiceCoach.self) private var voice
    @AppStorage(Settings.restTimeoutKey) private var restTimeout = 10.0
    @AppStorage(Settings.motivationKey) private var motivation = true
    @AppStorage(Settings.voiceKey) private var voiceName = ""
    @AppStorage(Settings.recordPosesKey) private var recordPoses = false
    @AppStorage(Settings.autoStartKey) private var autoStart = true

    var body: some View {
        Form {
            Section {
                Stepper(value: $restTimeout, in: 5...30, step: 1) {
                    Text("A set ends after **\(Int(restTimeout)) s** without a rep")
                }
                Toggle("Encouragement near the target", isOn: $motivation)
                Toggle("Start when I'm in position", isOn: $autoStart)
            } header: {
                Text("Coaching")
            } footer: {
                Text("Two reps before your target the coach starts cheering you on, and keeps asking for one more once you pass it. While you set up, the coach tells you where to stand, then counts down from three and starts on its own once you hold still in position.")
            }

            Section("Voice") {
                if voice.voices.isEmpty {
                    VoiceStatusRow(status: voice.status)
                } else {
                    Picker("Coach voice", selection: Binding(
                        get: { voice.voice ?? "" },
                        set: { name in
                            voiceName = name
                            Task { await voice.setVoice(name) }
                        })) {
                        ForEach(voice.voices, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Play a sample") {
                        voice.say([.init(PhraseBook.count(3), precomputed: true), .init(PhraseBook.lastOne, precomputed: true)])
                    }
                    LabeledContent("Status", value: voice.status.label)
                    if let rtf = voice.realtimeFactor {
                        LabeledContent("Speed on this iPhone", value: String(format: "%.1f× realtime", rtf))
                    }
                }
            }

            Section {
                Toggle("Record sensor data", isOn: $recordPoses)
            } header: {
                Text("Tuning")
            } footer: {
                Text("Saves what the sensors saw during each workout to Recordings in the Files app: detected joints (never video), how the phone was standing, and AirPods head motion. For push-ups it also runs body detection on the image turned sideways, which uses more battery. Replay the files on a Mac with repcoach-replay to tune the counting.")
            }
        }
        .navigationTitle("Settings")
    }
}
