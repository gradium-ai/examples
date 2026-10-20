import RepCoachCore
import SwiftUI

struct HomeView: View {
    @Environment(VoiceCoach.self) private var voice

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VoiceStatusRow(status: voice.status)

                Text("What are you training?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Exercise.allCases) { exercise in
                        NavigationLink(value: exercise) {
                            ExerciseCard(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Label("Everything runs on this iPhone. No network needed.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .navigationTitle("RepCoach")
        .navigationDestination(for: Exercise.self) { exercise in
            WorkoutView(exercise: exercise, voice: voice)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { HistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("History")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
    }
}

private struct ExerciseCard: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: exercise.symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(exercise.name)
                .font(.headline)
            Text("Target \(Settings.target(for: exercise))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct VoiceStatusRow: View {
    let status: VoiceCoach.Status

    var body: some View {
        HStack(spacing: 10) {
            switch status {
            case .ready:
                Image(systemName: "waveform").foregroundStyle(Theme.accent)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            default:
                ProgressView().controlSize(.small)
            }
            Text(status.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.05), in: Capsule())
    }
}
