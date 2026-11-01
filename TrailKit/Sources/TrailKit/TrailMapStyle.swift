import MapKit
import SwiftUI

extension MapStyle {
    /// Apple's standard map, muted so the route stands out, showing only places that matter on a
    /// hike. Scenic views, picnic areas, rest areas, ranger stations, visitor centres and
    /// information booths are new in iOS and watchOS 27.
    public static func trail(elevation: Elevation = .automatic) -> MapStyle {
        .standard(
            elevation: elevation, emphasis: .muted,
            pointsOfInterest: .including([
                .hiking, .nationalPark, .park, .campground, .landmark, .parking, .restroom,
                .scenicView, .picnicArea, .restArea, .rangerStation, .visitorCenter, .informationBooth,
            ]))
    }
}
