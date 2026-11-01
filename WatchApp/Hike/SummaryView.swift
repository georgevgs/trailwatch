import SwiftUI
import TrailKit

struct SummaryView: View {
    let session: HikeSession
    let onDone: () -> Void
    @State private var effort = 5
    @State private var effortSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(.done, in: .circle)

                VStack(spacing: 2) {
                    Text("Hike complete")
                        .font(.title3.bold())
                    Text(session.route.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        tile(Format.kilometres(session.distanceWalked), unit: "km", label: "Distance")
                        tile(Format.duration(session.elapsed), label: "Time")
                    }
                    GridRow {
                        tile("↑\(Format.metres(session.ascent))", unit: "m", label: "Ascent")
                        tile(Format.pace(seconds: session.elapsed, metres: session.distanceWalked) ?? "--",
                             unit: "/km", label: "Avg pace")
                    }
                }

                health
                    .font(.footnote)

                if session.workout.state == .saved {
                    effortRating
                }

                // Over the whole time out, pauses included: the battery drains either way.
                if let battery = session.battery, let end = session.endDate, end.timeIntervalSince(session.startDate) >= 600 {
                    let used = battery.atStart - battery.now
                    let perHour = Double(used) / (end.timeIntervalSince(session.startDate) / 3600)
                    Label("Battery used \(used.formatted(.percent.precision(.fractionLength(0)))), about \(perHour.formatted(.percent.precision(.fractionLength(0)))) an hour",
                          systemImage: "battery.50percent")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onDone) {
                    Text("Done")
                        .bold()
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .handGestureShortcut(.primaryAction)
            }
            .scenePadding(.horizontal)
        }
    }

    @ViewBuilder private var health: some View {
        switch session.workout.state {
        case .recording:
            HStack {
                ProgressView()
                    .frame(width: 20, height: 20)
                Text("Saving to Health…")
            }
        case .saved:
            Label("Saved to Health", systemImage: "heart.fill")
                .foregroundStyle(.pink)
        case .failed:
            Label("Couldn't save to Health", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        case .notRecording:
            Label("Not recorded in Health", systemImage: "heart.slash")
                .foregroundStyle(.secondary)
        }
    }

    /// Apple's 1–10 workout effort scale, saved with the workout for Fitness's training load.
    @ViewBuilder private var effortRating: some View {
        if effortSaved {
            Label("Effort \(effort) saved", systemImage: "checkmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 4) {
                Text("How hard was it?")
                    .font(.footnote.bold())
                Stepper(value: $effort, in: 1...10) {
                    Text("\(effort) \(Self.effortName(effort))")
                        .monospacedDigit()
                }
                Button("Save Effort") {
                    Task { effortSaved = await session.workout.rateEffort(effort) }
                }
                .buttonStyle(.glass)
            }
        }
    }

    /// The names Apple's Workout app gives the effort bands.
    private static func effortName(_ score: Int) -> String {
        switch score {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "All Out"
        }
    }

    private func tile(_ value: String, unit: String? = nil, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Text(label.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}
