import SwiftUI

struct ContentView: View {
    @ObservedObject var model: MirrorViewModel

    var body: some View {
        ZStack {
            // Status screens always sit on black so their white text stays readable.
            (model.phase.showsVideo ? model.backgroundStyle.color : Color.black)

            VideoView(
                model: model,
                mode: model.renderMode,
                videoSize: model.videoSize,
                gridStyle: model.gridStyle,
                roundedCorners: model.roundedCorners,
                background: model.backgroundStyle,
                inspectorEnabled: model.inspectorEnabled,
                autoHideCursor: model.autoHideCursor
            )
            .opacity(model.phase.showsVideo ? 1 : 0)

            if !model.phase.showsVideo {
                StatusView(model: model)
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                if case .stalled = model.phase {
                    Banner(text: "iPad bloccato o immagine ferma: in attesa di nuovi frame", symbol: "lock.fill")
                }
                if model.frozen, model.phase.showsVideo {
                    Banner(text: "Immagine congelata · barra spaziatrice per riprendere", symbol: "snowflake")
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, model.presentationMode ? 32 : 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)

            if model.phase.showsVideo {
                HStack(alignment: .bottom) {
                    if let info = model.inspector {
                        InspectorOverlay(info: info)
                    }
                    Spacer()
                    if model.zoom > 1.01 {
                        Text("\(Int((model.zoom * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(10)
                .allowsHitTesting(false)
            }

            if model.showStats, model.phase.showsVideo {
                StatsOverlay(stats: model.stats, deviceName: model.phase.deviceName ?? "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, model.presentationMode ? 28 : 0)
                    .padding(10)
                    .allowsHitTesting(false)
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
        .ignoresSafeArea()
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
                detail("Consenti l'accesso alla fotocamera: macOS tratta l'iPad come una sorgente video. Se non vedi la richiesta, attiva MirrorScreen in Impostazioni di Sistema › Privacy e sicurezza › Fotocamera.")
                Button("Apri Impostazioni di Sistema") { model.openCameraPrivacySettings() }

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

struct Banner: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
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

struct InspectorOverlay: View {
    let info: PixelInfo

    var body: some View {
        HStack(spacing: 8) {
            if let hex = info.hex, let color = Color(hex: hex) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.6), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(info.x), \(info.y) px · \(info.pointX), \(info.pointY) pt")
                Text(info.hex.map { "\($0) · clic per copiare" } ?? "colore solo con formato BGRA")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension Color {
    /// Parses "#RRGGBB".
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
