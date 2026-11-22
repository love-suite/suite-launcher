import AppKit

/// Full-screen overlay for the app grid, shown over whatever is on screen: on the current Space,
/// over full-screen apps too, and taking the keyboard without activating Launcher (like Spotlight).
final class LauncherWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: 490) // below kCGDraggingWindowLevel (500), above all app windows
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
