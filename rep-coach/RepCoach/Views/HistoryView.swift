import RepCoachCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private var days: [(day: Date, records: [WorkoutRecord])] {
        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "figure.strengthtraining.traditional",
                                       description: Text("Finished sessions show up here."))
            }
            ForEach(days, id: \.day) { day in
                Section(day.day.formatted(.dateTime.weekday(.wide).day().month())) {
                    ForEach(day.records) { record in
                        HStack(spacing: 14) {
                            Image(systemName: record.exercise.symbol)
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.exercise.name).font(.headline)
                                Text(record.sets.map(String.init).joined(separator: " · "))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(record.totalReps)").font(.title3.weight(.bold).monospacedDigit())
                                Text(record.date.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(day.records[i]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
