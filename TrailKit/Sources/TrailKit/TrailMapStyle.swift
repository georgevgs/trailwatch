import MapKit
import SwiftUI

extension MapStyle {
    /// Muted Apple map showing only places that matter on a hike (some categories new in 27).
    public static func trail(elevation: Elevation = .automatic) -> MapStyle {
        .standard(
            elevation: elevation, emphasis: .muted,
            pointsOfInterest: .including([
                .hiking, .nationalPark, .park, .campground, .landmark, .parking, .restroom,
                .scenicView, .picnicArea, .restArea, .rangerStation, .visitorCenter, .informationBooth,
            ]))
    }
}
