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

    private var spaceObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

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

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.hide() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, activated?.processIdentifier != getpid(), self.window.isVisible else { return }
            self.hide()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        window.setFrame(screen?.frame ?? .zero, display: true)
        window.makeKeyAndOrderFront(nil)
        viewController.prepareToShow()
    }

    func hide() {
        window.orderOut(nil)
        NSApp.deactivate()
    }
}
