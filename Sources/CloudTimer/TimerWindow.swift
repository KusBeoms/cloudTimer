import AppKit
import SwiftUI

final class TimerNSWindow: NSWindow, NSWindowDelegate {
    /// Normal state: float on every Space, including over other apps' full-screen Spaces.
    static let floatingBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    var keyHandler: ((NSEvent) -> Bool)?

    /// Call once after configuring the window: floating on all Spaces, with the green button / F key
    /// switching to a real full-screen Space (a window cannot be both all-Spaces and full-screen primary).
    func installFullScreenSupport() {
        delegate = self
        collectionBehavior = Self.floatingBehavior
        if let zoom = standardWindowButton(.zoomButton) {
            zoom.target = self
            zoom.action = #selector(toggleTimerFullScreen(_:))
            zoom.isEnabled = true
        }
    }

    @objc func toggleTimerFullScreen(_ sender: Any?) {
        if !styleMask.contains(.fullScreen) {
            collectionBehavior = [.fullScreenPrimary]
        }
        toggleFullScreen(nil)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        collectionBehavior = Self.floatingBehavior
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class TimerWindowManager {
    static let shared = TimerWindowManager()

    private var windows: [NSWindow] = []
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var nextPoint = NSPoint.zero

    private init() {}

    func open(_ preset: Preset) {
        // The J-key 작전타임 card; not offered inside the 작전타임 preset's own window.
        let tactical = PresetStore.shared.tacticalPreset.flatMap { $0.id == preset.id ? nil : $0 }
        let session = TimerSession(preset: preset, tactical: tactical)

        let host = NSHostingView(rootView: TimerView(session: session))
        host.sizingOptions = []

        let win = TimerNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = host
        win.setContentSize(NSSize(width: 960, height: 560))
        win.minSize = NSSize(width: 640, height: 380)
        win.title = preset.name
        win.titlebarAppearsTransparent = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.14, alpha: 1)
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.installFullScreenSupport()
        win.isReleasedWhenClosed = false

        win.keyHandler = { [weak win] event in
            if event.isARepeat { return false }
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            if mods == [.command, .control], event.keyCode == 3 {   // ⌃⌘F: full screen
                MainActor.assumeIsolated { win?.toggleTimerFullScreen(nil) }
                return true
            }
            if !mods.isEmpty { return false }
            switch event.keyCode {
            case 49:            // Space: start (intro) / pause-resume / start-stop 작전타임
                MainActor.assumeIsolated { session.primaryAction() }
            case 36, 76:        // Return / Enter: start (intro) / next step / dismiss 작전타임
                MainActor.assumeIsolated { session.advanceAction() }
            case 3:             // F: 빨강팀 작전타임
                MainActor.assumeIsolated { session.tacticalKey(.red) }
            case 38:            // J: 파랑팀 작전타임
                MainActor.assumeIsolated { session.tacticalKey(.blue) }
            case 123:           // ←: previous step
                MainActor.assumeIsolated { session.previous() }
            default:
                return false
            }
            return true
        }

        let key = ObjectIdentifier(win)
        observers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { [weak self, weak win] _ in
            MainActor.assumeIsolated {
                session.stop()
                guard let self else { return }
                if let win { self.windows.removeAll { $0 === win } }
                if let token = self.observers.removeValue(forKey: key) {
                    NotificationCenter.default.removeObserver(token)
                }
            }
        }

        if windows.isEmpty {
            win.center()
            nextPoint = NSPoint(x: win.frame.minX, y: win.frame.maxY)
        }
        nextPoint = win.cascadeTopLeft(from: nextPoint)
        windows.append(win)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
