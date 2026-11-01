import Foundation

/// The provisioning profile inside the app, which says when a development install stops opening.
public enum ProvisioningProfile {
    /// When this install stops opening; nil for App Store and TestFlight builds, which carry no profile.
    public static let appExpirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return expirationDate(in: data)
    }()

    /// Reads `ExpirationDate` from a profile: a signed blob with a property list inside.
    static func expirationDate(in data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil)
        else { return nil }
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }
}
