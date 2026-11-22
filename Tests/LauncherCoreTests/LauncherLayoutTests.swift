import Foundation
import Testing
@testable import LauncherCore

private let sorted: [GridEntry] = [.folder("F"), .app("a"), .app("b"), .app("c")]

private func tempStore() -> LauncherFolderStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherCoreTests-" + UUID().uuidString)
    return LauncherFolderStore(directory: dir)
}

@Test func entryKeysRoundTrip() {
    for entry in [GridEntry.folder("1A-2B"), .app("com.apple.Safari"), .app("/Applications/My App.app")] {
        #expect(GridEntry(key: entry.key) == entry)
    }
    #expect(GridEntry(key: "x:1") == nil)
}

@Test func sortedOrderWhenNotCustom() {
    #expect(LauncherLayout(isCustom: false, order: ["a:c", "a:a"]).arrange(sorted) == sorted)
}

@Test func customOrderKeepsUnknownItemsLastAndDropsGoneOnes() {
    let layout = LauncherLayout(isCustom: true, order: ["a:c", "a:gone", "f:F", "a:c"])
    #expect(layout.arrange(sorted) == [.app("c"), .folder("F"), .app("a"), .app("b")])
}

@Test func movingForwardAndBackward() {
    #expect(LauncherLayout.moving(.app("a"), before: 3, in: sorted).order == ["f:F", "a:b", "a:a", "a:c"])
    #expect(LauncherLayout.moving(.app("c"), before: 0, in: sorted).order == ["a:c", "f:F", "a:a", "a:b"])
    #expect(LauncherLayout.moving(.app("a"), before: 99, in: sorted).order == ["f:F", "a:b", "a:c", "a:a"])
    #expect(LauncherLayout.moving(.app("a"), before: 1, in: sorted).order == sorted.map(\.key))
}

@Test func movingInAnAppFromAFolder() {
    let layout = LauncherLayout.moving(.app("x"), before: 2, in: sorted)
    #expect(layout.isCustom)
    #expect(layout.order == ["f:F", "a:a", "a:x", "a:b", "a:c"])
}

@Test func lastAppTakesItsFolderPlace() {
    let store = tempStore()
    store.add(LauncherFolder(id: "F", name: "Games", appIDs: ["x", "y"]))
    store.setLayout(LauncherLayout(isCustom: true, order: ["a:a", "f:F", "a:y", "a:b"]))
    #expect(store.takeApp("x", outOf: "F") == "y")
    #expect(store.folders.isEmpty)
    #expect(store.layout.order == ["a:a", "a:y", "a:b"])
}

@Test func folderWithAppsLeftStays() {
    let store = tempStore()
    store.add(LauncherFolder(id: "F", name: "Games", appIDs: ["x", "y", "z"]))
    #expect(store.takeApp("x", outOf: "F") == nil)
    #expect(store.folders.first?.appIDs == ["y", "z"])
}

@Test func reloadForgetsWhatIsNoLongerSaved() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherCoreTests-" + UUID().uuidString)
    let store = LauncherFolderStore(directory: dir)
    store.add(LauncherFolder(name: "Games"))
    store.setLayout(LauncherLayout(isCustom: true, order: ["a:a"]))
    try FileManager.default.removeItem(at: dir)
    store.reload()
    #expect(store.folders.isEmpty)
    #expect(store.layout == LauncherLayout())
}

@Test func storeKeepsLayoutAcrossLaunches() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherCoreTests-" + UUID().uuidString)
    LauncherFolderStore(directory: dir).setLayout(LauncherLayout(isCustom: true, order: ["a:a"]))
    #expect(LauncherFolderStore(directory: dir).layout == LauncherLayout(isCustom: true, order: ["a:a"]))
}
