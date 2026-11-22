import Foundation

/// An application found on this Mac.
public struct AppItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let bundleID: String?
    public let modificationDate: Date?

    public init(url: URL) {
        self.url = url
        let bundle = Bundle(url: url)
        bundleID = bundle?.bundleIdentifier
        id = bundle?.bundleIdentifier ?? url.path
        name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    public var categoryName: String? {
        guard let cat = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String
        else { return nil }
        return cat.components(separatedBy: ".").last?.capitalized
    }
}
