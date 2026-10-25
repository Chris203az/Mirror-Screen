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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct MirrorCommands: Commands {
    @ObservedObject var model: MirrorViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Mirroring") {
            Button("Dimensione reale") { model.windowManager.actualSize() }
                .keyboardShortcut("1")
                .disabled(!model.hasVideo)
            Button("Adatta allo schermo") { model.windowManager.fitToScreen() }
                .keyboardShortcut("2")
                .disabled(!model.hasVideo)
            // ⌃⌘F is already bound by the system "Enter Full Screen" item.
            Button("Schermo intero") { model.windowManager.toggleFullScreen() }

            Divider()

            Toggle("Sempre in primo piano", isOn: $model.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Toggle("Mostra statistiche", isOn: $model.showStats)
                .keyboardShortcut("i")

            Divider()

            Button("Copia schermata") { model.copySnapshot() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.hasVideo)
            Button("Riconnetti") { model.reconnect() }
                .keyboardShortcut("r")

            Divider()

            Picker("Dispositivo", selection: Binding(
                get: { model.activeDeviceID ?? "" },
                set: { model.selectDevice($0) }
            )) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .disabled(model.devices.isEmpty)
        }
    }
}
