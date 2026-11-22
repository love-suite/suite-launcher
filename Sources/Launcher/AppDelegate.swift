import AppKit
import LauncherCore
import SuiteCore

/// Ties the pieces together: a `LauncherMessage.open` (Bar's Launcher tile)
/// shows the full-screen grid; choosing an app or pressing Esc/clicking outside hides it.
final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var window = LauncherWindow()
    private lazy var viewController = LauncherViewController()
    private let settings = LauncherSettings()

    /// Launcher keeps itself up to date from its own releases, once its grid is closed.
    static let updater = SuiteUpdater(appName: "Launcher")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.updater.start()
        window.contentViewController = viewController
        viewController.onDismiss = { [weak self] in self?.hide() }
        viewController.settings = settings

        LauncherMessage.open.observe { [weak self] _ in self?.show() }
        LauncherMessage.settingsDidChange.observe { [weak self] _ in
            guard let self else { return }
            settings.reload()
            viewController.settings = settings
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func show() {
        window.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewController.prepareToShow()
    }

    func hide() {
        window.orderOut(nil)
        NSApp.deactivate()
    }
}
