import AppKit
import SuiteCore

/// Launcher: Launchpad replacement for macOS. Started on demand; a click on Bar's Launcher tile (when
/// added) or a `LauncherMessage.open` shows the grid.
// Reopened by the previous copy (an update): once it is gone, this copy carries on.
AppRelauncher.waitForPreviousCopy()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LauncherAppDelegate()
app.delegate = delegate
app.run()
