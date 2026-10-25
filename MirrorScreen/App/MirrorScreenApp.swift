import AppKit
import SwiftUI

@main
struct MirrorScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MirrorViewModel()

    var body: some Scene {
        Window("MirrorScreen", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 560, height: 800)
        .commands {
            MirrorCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra("MirrorScreen", systemImage: model.menuBarSymbol, isInserted: $model.showMenuBarIcon) {
            MenuBarContent(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // With the menu bar icon on, closing the window keeps the app (and the mirroring) alive.
        !UserDefaults.standard.bool(forKey: "showMenuBarIcon")
    }
}
