import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CloudTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("cloudTimer 프리셋 편집기", id: "editor") {
            EditorView()
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            TimerCommands()
        }
    }
}

struct TimerCommands: Commands {
    @ObservedObject private var store = PresetStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("프리셋으로 타이머 열기") {
                ForEach(store.presets) { preset in
                    Button(preset.name) {
                        TimerWindowManager.shared.open(preset)
                    }
                }
            }

            Button("프리셋 편집기 열기") {
                openWindow(id: "editor")
            }
            .keyboardShortcut("e")
        }
    }
}
