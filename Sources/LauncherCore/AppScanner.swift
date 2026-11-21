import Foundation

/// Scans the standard applications folders for installed apps.
public enum AppScanner {
    static let searchPaths: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    /// All installed apps from the standard locations, sorted by name.
    public static func scan() -> [AppItem] {
        var seen = Set<String>()
        var apps: [AppItem] = []
        let fm = FileManager.default
        for base in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            else { continue }
            for url in contents where url.pathExtension == "app" {
                let item = AppItem(url: url)
                guard seen.insert(item.id).inserted else { continue }
                apps.append(item)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
