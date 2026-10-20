import SwiftData
import SwiftUI

@main
struct RepCoachApp: App {
    @State private var voice = VoiceCoach()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(voice)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .task {
                await voice.prepare(voiceName: UserDefaults.standard.string(forKey: Settings.voiceKey))
            }
        }
        .modelContainer(for: WorkoutRecord.self)
    }
}

enum Theme {
    static let accent = Color(red: 0.78, green: 1.0, blue: 0.24)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let panel = Color.black.opacity(0.6)
}
