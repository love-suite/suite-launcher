import Foundation

/// An application found on this Mac.
public struct AppItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let bundleID: String?

    public init(url: URL) {
        self.url = url
        let bundle = Bundle(url: url)
        bundleID = bundle?.bundleIdentifier
        id = bundle?.bundleIdentifier ?? url.path
        name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
