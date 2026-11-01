import SwiftUI

extension RouteLibrary {
    /// Applies a drag in a list made `reorderable()` (iOS and watchOS 27).
    public func apply(_ difference: ReorderDifference<UUID, ReorderableSingleCollectionIdentifier>) throws {
        switch difference.destination.position {
        case .before(let target): try move(difference.sources, before: target)
        case .end: try move(difference.sources, before: nil)
        }
    }
}
