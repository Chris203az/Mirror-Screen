import SwiftUI

struct ContentView: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        ZStack {
            Color.black

            VideoView(model: model, mode: model.renderMode)
                .opacity(model.phase.showsVideo ? 1 : 0)

            if !model.phase.showsVideo {
                StatusView(model: model)
                    .transition(.opacity)
            }

            if case .stalled = model.phase {
                StalledBanner()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.showStats, model.phase.showsVideo {
                StatsOverlay(stats: model.stats, deviceName: model.phase.deviceName ?? "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .frame(minWidth: 240, minHeight: 240)
        .background(WindowAccessor { window in model.windowManager.attach(window) })
        .navigationTitle(model.windowTitle)
        .onAppear { model.start() }
    }
}

struct StatusView: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        VStack(spacing: 14) {
            switch model.phase {
            case .needsPermission:
                ProgressView().controlSize(.large)
                title("Richiesta di accesso…")
                detail("Consenti l'accesso alla fotocamera: macOS tratta l'iPad come una sorgente video.")

            case .permissionDenied:
                icon("lock.fill")
                title("Accesso non consentito")
                detail("Consenti a MirrorScreen l'uso della Fotocamera in Impostazioni di Sistema › Privacy e sicurezza, poi riavvia l'app.")
                Button("Apri Impostazioni di Sistema") { model.openCameraPrivacySettings() }

            case .waitingForDevice:
                icon("ipad")
                title("Collega un iPad")
                detail("Usa un cavo USB e sblocca l'iPad. Se richiesto, tocca «Autorizza» sull'iPad. Il primo collegamento può richiedere qualche secondo.")

            case .connecting(let name):
                ProgressView().controlSize(.large)
                title("Connessione a \(name)…")
                detail("Tieni l'iPad sbloccato.")

            case .disconnected(let name):
                icon("cable.connector.slash")
                title("\(name) scollegato")
                detail("Il mirroring riprende da solo quando lo ricolleghi.")

            case .failed(let message):
                icon("exclamationmark.triangle")
                title("Errore di cattura")
                detail(message)
                Button("Riprova") { model.reconnect() }

            case .streaming, .stalled:
                EmptyView()
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(.white.opacity(0.85))
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
    }
}

struct StalledBanner: View {
    var body: some View {
        Label("iPad bloccato o immagine ferma: in attesa di nuovi frame", systemImage: "lock.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }
}

struct StatsOverlay: View {
    let stats: StreamStats
    let deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deviceName).fontWeight(.semibold)
            Text("\(Int(stats.resolution.width))×\(Int(stats.resolution.height)) · \(stats.pixelFormat)")
            Text(String(format: "%.1f fps · %llu persi", stats.fps, stats.dropped))
            Text(String(format: "ultimo frame %.2f s fa", stats.secondsSinceLastFrame))
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}
