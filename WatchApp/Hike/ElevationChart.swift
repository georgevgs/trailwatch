import Charts
import SwiftUI
import TrailKit

/// The route's height along its length, and where you are on it.
struct ElevationChart: View {
    let profile: ElevationProfile
    var along: Double?

    var body: some View {
        let samples = profile.chartSamples()
        let low = samples.map(\.elevation).min() ?? 0
        let high = max(samples.map(\.elevation).max() ?? 0, low + 10)

        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                AreaMark(
                    x: .value("Distance", sample.distance),
                    yStart: .value("Lowest", low), yEnd: .value("Elevation", sample.elevation))
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                LineMark(x: .value("Distance", sample.distance), y: .value("Elevation", sample.elevation))
                    .foregroundStyle(Color.accentColor)
            }
            if let along {
                RuleMark(x: .value("You", along))
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(profile.length, 1))
        .chartYScale(domain: low...high)
        .accessibilityElement()
        .accessibilityLabel("Elevation profile")
        .accessibilityValue("\(Format.metres(low)) to \(Format.metres(high)) metres")
    }
}
