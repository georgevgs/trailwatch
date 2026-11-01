import SwiftUI
import TrailKit

struct StatsView: View {
    let session: HikeSession

    var body: some View {
        let along = session.tracker.distanceAlong
        let profile = session.finish.profile
        let timeLeft = session.timeToFinish

        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label(session.isPaused ? "PAUSED" : "HIKING", systemImage: session.isPaused ? "pause.fill" : "figure.hiking")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(session.isPaused ? Color.yellow : Color.done)

                Text(timerInterval: session.stopwatch.countingFrom...Date.distantFuture,
                     pauseTime: session.stopwatch.pausedAt, countsDown: false)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)

                metric(Format.kilometres(session.distanceWalked), unit: "KM")
                metric("↑\(Format.metres(session.ascent))", unit: "M", label: "ASCENT")
                metric(Format.pace(seconds: session.elapsed, metres: session.distanceWalked) ?? "--", unit: "/KM")
                if let heartRate = session.workout.heartRate {
                    metric(heartRate.formatted(.number.precision(.fractionLength(0))), unit: "BPM",
                           label: session.workout.heartRateZone.map { "ZONE \($0)" })
                }

                if profile.hasElevation {
                    ElevationChart(profile: profile, along: along)
                        .frame(height: 44)
                        .padding(.top, 4)
                    Text("↑ \(Format.metres(profile.climb(after: along))) m  ↓ \(Format.metres(profile.descent(after: along))) m left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Label("\(Format.hoursMinutes(timeLeft)) to finish, about \((Date.now + timeLeft).formatted(.dateTime.hour().minute()))",
                      systemImage: "flag.checkered")
                    .font(.footnote)
                if let sunset = session.sunset {
                    Label("Sunset \(sunset.formatted(.dateTime.hour().minute()))", systemImage: "sunset.fill")
                        .font(.footnote)
                        .foregroundStyle(session.finishesAfterDark ? Color.orange : Color.secondary)
                }

                if let battery = session.battery {
                    Label("Battery \(battery.now.formatted(.percent.precision(.fractionLength(0))))",
                          systemImage: "battery.75percent")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let stop = session.nextStop {
                    Label {
                        Text("\(stop.waypoint.name) in \(Format.kilometres(stop.distanceAlong - along)) km")
                    } icon: {
                        Image(systemName: "mappin")
                    }
                    .font(.footnote)
                    .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Format.kilometres(session.tracker.distanceRemaining)) km to go")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ProgressView(value: session.progress)
                }
                .padding(.top, 6)

                HStack {
                    Button("End", systemImage: "xmark", role: .destructive) {
                        session.showsEndDialog = true
                    }
                    PauseButton(session: session)
                }
                .buttonStyle(.glass)
                .padding(.top, 6)
            }
            .monospacedDigit()
        }
    }

    private func metric(_ value: String, unit: String, label: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(unit)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(.secondary)
            if let label {
                Text(label)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
