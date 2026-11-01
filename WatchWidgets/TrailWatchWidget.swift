import SwiftUI
import TrailKit
import WidgetKit

/// Puts TrailWatch on watch faces and in the Smart Stack: one tap from a hike, and the hike's
/// progress while one is running.
@main
struct TrailWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HikeGlance.widgetKind, provider: HikeProvider()) { entry in
            HikeComplication(hike: entry.hike)
        }
        .configurationDisplayName("TrailWatch")
        .description("Shows your hike's progress, or opens TrailWatch to start one.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct HikeEntry: TimelineEntry {
    let date: Date
    /// The hike in progress, if any.
    let hike: HikeGlance?
}

/// The Watch app reloads this as the hike goes. If it stops (the app quit), the complication goes
/// back to a launcher after half an hour rather than showing old progress.
nonisolated struct HikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HikeEntry {
        HikeEntry(date: .now, hike: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HikeEntry) -> Void) {
        completion(HikeEntry(date: .now, hike: HikeGlance.shared))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HikeEntry>) -> Void) {
        let staleAfter = 30.0 * 60
        guard let hike = HikeGlance.shared, Date.now.timeIntervalSince(hike.updated) < staleAfter else {
            completion(Timeline(entries: [HikeEntry(date: .now, hike: nil)], policy: .never))
            return
        }
        completion(Timeline(entries: [
            HikeEntry(date: .now, hike: hike),
            HikeEntry(date: hike.updated + staleAfter, hike: nil),
        ], policy: .never))
    }
}

struct HikeComplication: View {
    let hike: HikeGlance?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color(red: 0x1B / 255, green: 0x2A / 255, blue: 0x22 / 255)
            }
    }

    @ViewBuilder private var content: some View {
        switch (family, hike) {
        case (.accessoryCircular, let hike?):
            Gauge(value: hike.progress) {
                Image(systemName: symbol(hike))
            } currentValueLabel: {
                Text(shortKilometres(hike.distanceRemaining))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case (.accessoryCorner, let hike?):
            Image(systemName: symbol(hike))
                .font(.title2)
                .widgetLabel {
                    ProgressView(value: hike.progress)
                        .widgetAccentable()
                }
        case (.accessoryRectangular, let hike?):
            VStack(alignment: .leading, spacing: 1) {
                Label(hike.routeName, systemImage: symbol(hike))
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                // Counts by itself, so it stays right between reloads.
                Text(timerInterval: hike.countingFrom...Date.distantFuture, pauseTime: hike.pausedAt, countsDown: false)
                    .monospacedDigit()
                Text(detail(hike))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: hike.progress)
                    .widgetAccentable()
            }
        case (.accessoryInline, let hike?):
            Label(hike.isPaused ? "Paused · \(Format.kilometres(hike.distanceRemaining)) km to go"
                                : "\(Format.kilometres(hike.distanceRemaining)) km to go",
                  systemImage: symbol(hike))
        case (.accessoryCorner, nil):
            Image(systemName: "figure.hiking")
                .font(.title2)
                .widgetLabel("TrailWatch")
        case (.accessoryRectangular, nil):
            HStack {
                Image(systemName: "figure.hiking")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text("TrailWatch")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Start a hike")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case (.accessoryInline, nil):
            Label("TrailWatch", systemImage: "figure.hiking")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.hiking")
                    .font(.title2)
                    .widgetAccentable()
            }
        }
    }

    private func symbol(_ hike: HikeGlance) -> String {
        hike.isPaused ? "pause.fill" : "figure.hiking"
    }

    /// "3.2": kilometres to go, short enough for the circular gauge.
    private func shortKilometres(_ metres: Double) -> String {
        (metres / 1000).formatted(.number.precision(.fractionLength(1)))
    }

    private func detail(_ hike: HikeGlance) -> String {
        let left = "\(Format.kilometres(hike.distanceRemaining)) km to go"
        guard let arrival = hike.arrival else { return hike.isPaused ? "Paused · \(left)" : left }
        return "\(left) · \(arrival.formatted(.dateTime.hour().minute()))"
    }
}
