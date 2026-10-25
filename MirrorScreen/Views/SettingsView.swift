import SwiftUI

struct SettingsView: View {
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
                Toggle("Sempre in primo piano", isOn: $model.alwaysOnTop)
                Toggle("Mostra statistiche", isOn: $model.showStats)
            }

            Section("Blocco dell'iPad") {
                Toggle("Segnala quando non arrivano nuovi frame", isOn: $model.stallDetection)
                Stepper(value: $model.stallTimeout, in: 1...15, step: 0.5) {
                    Text("Dopo \(model.stallTimeout, specifier: "%.1f") secondi")
                }
                .disabled(!model.stallDetection)
            }

            Section("Sistema") {
                Toggle("Impedisci lo stop dello schermo durante il mirroring", isOn: $model.preventSleep)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
