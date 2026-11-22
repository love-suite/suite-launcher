import Foundation

public struct LauncherFolder: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var appIDs: [String]

    public init(id: String = UUID().uuidString, name: String, appIDs: [String] = []) {
        self.id = id; self.name = name; self.appIDs = appIDs
    }
}

/// What the grid shows, by id: a folder or an app that is in no folder.
public enum GridEntry: Hashable, Sendable {
    case folder(String)
    case app(String)

    /// How it is written in the saved order.
    public var key: String {
        switch self {
        case .folder(let id): return "f:" + id
        case .app(let id): return "a:" + id
        }
    }

    public init?(key: String) {
        let id = String(key.dropFirst(2))
        switch key.prefix(2) {
        case "f:": self = .folder(id)
        case "a:": self = .app(id)
        default: return nil
        }
    }
}

/// The grid in the order the user gave it by dragging (Custom), or in the order of the sort.
public struct LauncherLayout: Codable, Equatable, Sendable {
    public var isCustom: Bool
    public var order: [String]

    public init(isCustom: Bool = false, order: [String] = []) {
        self.isCustom = isCustom; self.order = order
    }

    /// `sorted` (folders then apps, as the sort puts them) in the custom order when there is one: what the
    /// order doesn't know yet (an app just installed) comes last, in sorted order.
    public func arrange(_ sorted: [GridEntry]) -> [GridEntry] {
        guard isCustom else { return sorted }
        let present = Set(sorted)
        var seen = Set<GridEntry>()
        var result = order.compactMap(GridEntry.init(key:)).filter { present.contains($0) && seen.insert($0).inserted }
        result += sorted.filter { !seen.contains($0) }
        return result
    }

    /// The custom order of `shown` with `entry` taken from where it was and put before `shown[index]`
    /// (after the last item when `index` is past the end).
    public static func moving(_ entry: GridEntry, before index: Int, in shown: [GridEntry]) -> LauncherLayout {
        var list = shown
        var target = min(max(index, 0), list.count)
        if let from = list.firstIndex(of: entry) {
            list.remove(at: from)
            if from < target { target -= 1 }
        }
        list.insert(entry, at: target)
        return LauncherLayout(isCustom: true, order: list.map(\.key))
    }

    /// `new` in the place of `old` (an app taking the place of its dissolved folder), and nowhere else.
    public func replacing(_ old: GridEntry, with new: GridEntry) -> LauncherLayout {
        var order = self.order.filter { $0 != new.key }
        if let i = order.firstIndex(of: old.key) { order[i] = new.key }
        return LauncherLayout(isCustom: isCustom, order: order)
    }
}

public final class LauncherFolderStore {
    public private(set) var folders: [LauncherFolder] = []
    public private(set) var layout = LauncherLayout()
    private let fileURL: URL
    private let layoutURL: URL

    /// `directory`: where the folders and the order are kept, Application Support/Explorer/Launcher by default.
    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Explorer/Launcher")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("folders.json")
        layoutURL = dir.appendingPathComponent("layout.json")
        reload()
    }

    public func reload() {
        folders = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([LauncherFolder].self, from: $0) } ?? []
        layout = (try? Data(contentsOf: layoutURL))
            .flatMap { try? JSONDecoder().decode(LauncherLayout.self, from: $0) } ?? LauncherLayout()
    }

    public func add(_ folder: LauncherFolder) { folders.append(folder); save() }

    public func update(_ folder: LauncherFolder) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i] = folder; save()
    }

    public func remove(id: String) { folders.removeAll { $0.id == id }; save() }

    public func appIDsInFolders() -> Set<String> { Set(folders.flatMap(\.appIDs)) }

    public func setLayout(_ layout: LauncherLayout) {
        self.layout = layout
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: layoutURL)
    }

    /// Takes `appID` out of the folder. A folder left with a single app goes, that app taking its place
    /// in the custom order; its id is returned.
    @discardableResult
    public func takeApp(_ appID: String, outOf folderID: String) -> String? {
        guard var folder = folders.first(where: { $0.id == folderID }) else { return nil }
        folder.appIDs.removeAll { $0 == appID }
        guard folder.appIDs.count == 1, let last = folder.appIDs.first else {
            update(folder)
            return nil
        }
        remove(id: folderID)
        setLayout(layout.replacing(.folder(folderID), with: .app(last)))
        return last
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: fileURL)
    }
}
