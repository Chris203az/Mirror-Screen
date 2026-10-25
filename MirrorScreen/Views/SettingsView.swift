import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("Generale", systemImage: "gearshape") }
            AppearanceSettings(model: model)
                .tabItem { Label("Aspetto", systemImage: "paintbrush") }
            AdvancedSettings(model: model)
                .tabItem { Label("Avanzate", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        Form {
            Section("Finestra") {
                Toggle("Sempre in primo piano", isOn: $model.alwaysOnTop)
                Toggle("Modalità presentazione (senza barra del titolo)", isOn: $model.presentationMode)
            }
            Section("Sistema") {
                Toggle("Impedisci lo stop dello schermo durante il mirroring", isOn: $model.preventSleep)
                Toggle("Icona nella barra dei menu", isOn: $model.showMenuBarIcon)
                Toggle("Avvia MirrorScreen al login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Notifica quando l'iPad si collega o si scollega", isOn: $model.notifyConnections)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        Form {
            Section("Immagine") {
                Picker("Sfondo", selection: $model.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Angoli arrotondati come l'iPad", isOn: $model.roundedCorners)
                Picker("Griglia", selection: $model.gridStyle) {
                    ForEach(GridStyle.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Finestra") {
                LabeledContent("Opacità") {
                    Slider(value: $model.windowOpacity, in: 0.3...1)
                }
                Toggle("Nascondi il cursore quando è fermo sull'immagine", isOn: $model.autoHideCursor)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AdvancedSettings: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        Form {
            Section("Visualizzazione") {
                Picker("Motore", selection: $model.renderMode) {
                    ForEach(RenderMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Formato pixel", selection: $model.pixelFormat) {
                    ForEach(PixelFormatPreference.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Mostra statistiche", isOn: $model.showStats)
            }
            Section("Blocco dell'iPad") {
                Toggle("Segnala quando non arrivano nuovi frame", isOn: $model.stallDetection)
                Stepper(value: $model.stallTimeout, in: 1...15, step: 0.5) {
                    Text("Dopo \(model.stallTimeout, specifier: "%.1f") secondi")
                }
                .disabled(!model.stallDetection)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
