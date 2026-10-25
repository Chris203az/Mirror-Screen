import AppKit
import SwiftUI

struct MirrorCommands: Commands {
    @ObservedObject var model: MirrorViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Mirroring") {
            Menu("Dimensione finestra") {
                Button("50%") { model.windowManager.scale(by: 0.5) }
                Button("75%") { model.windowManager.scale(by: 0.75) }
                Button("Dimensione reale") { model.windowManager.actualSize() }
                    .keyboardShortcut("1")
                Button("Adatta allo schermo") { model.windowManager.fitToScreen() }
                    .keyboardShortcut("2")
            }
            .disabled(!model.hasVideo)
            // ⌃⌘F is already bound by the system "Enter Full Screen" item.
            Button("Schermo intero") { model.windowManager.toggleFullScreen() }
            Toggle("Modalità presentazione", isOn: $model.presentationMode)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Toggle("Sempre in primo piano", isOn: $model.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Ingrandisci") { model.zoomIn() }
                .keyboardShortcut("=")
                .disabled(!model.hasVideo)
            Button("Riduci") { model.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!model.hasVideo || model.zoom <= 1)
            Button("Zoom 100%") { model.resetZoom() }
                .keyboardShortcut("0")
                .disabled(model.zoom <= 1)

            Divider()

            Toggle("Congela immagine", isOn: $model.frozen)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.hasVideo)
            Button("Copia schermata") { model.copySnapshot() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.hasVideo)
            Toggle("Ispettore pixel", isOn: $model.inspectorEnabled)
                .keyboardShortcut("i", modifiers: [.command, .option])
            Picker("Griglia", selection: $model.gridStyle) {
                ForEach(GridStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Angoli arrotondati", isOn: $model.roundedCorners)
            Toggle("Mostra statistiche", isOn: $model.showStats)
                .keyboardShortcut("i")

            Divider()

            Button("Riconnetti") { model.reconnect() }
                .keyboardShortcut("r")
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

struct MenuBarContent: View {
    @ObservedObject var model: MirrorViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusLine)
        Divider()
        Button("Mostra finestra") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Riconnetti") { model.reconnect() }
        Toggle("Congela immagine", isOn: $model.frozen)
            .disabled(!model.hasVideo)
        Toggle("Sempre in primo piano", isOn: $model.alwaysOnTop)
        Toggle("Modalità presentazione", isOn: $model.presentationMode)
        Divider()
        Button("Esci da MirrorScreen") { NSApp.terminate(nil) }
    }
}
