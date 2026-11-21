import AppKit

/// Explorer Launcher: Launchpad replacement for macOS. Launched by Explorer on demand; a click on
/// the Launcher tile in Explorer's Dock (when added) or a `LauncherMessage.open` shows the grid.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LauncherAppDelegate()
app.delegate = delegate
app.run()
