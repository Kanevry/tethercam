import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var listenerState = "startet"
    @Published var stats = UsbServer.Stats()
    @Published var selectedCameraId: UInt8 = 0
    @Published var keepScreenOn = true { didSet { applyIdleTimer() } }
    @Published var cameraDenied = false
    /// Default on: the phone hangs in a tripod mount whose orientation the app
    /// cannot know, so the horizon-level angle is the only honest source.
    @Published var autoRotation = true { didSet { capture.autoRotation = autoRotation } }
    /// Only effective while `autoRotation` is off.
    @Published var manualRotation: Int = 0 {
        didSet { capture.manualRotationAngle = CGFloat(manualRotation) }
    }
    /// Continuous levelling on top of the 90-degree sector. Persisted by the
    /// view via @AppStorage; default on.
    @Published var horizonLeveling = true {
        didSet { capture.horizonLeveling = horizonLeveling }
    }
    /// Refreshed once per second from the server tick — no extra timer.
    @Published var leveler = HorizonLeveler.Telemetry()

    let capture = CaptureEngine()
    private lazy var server = UsbServer(capture: capture)

    var cameras: [CameraDescriptor] { capture.descriptors }

    func boot() {
        applyIdleTimer()
        server.onListenerState = { [weak self] s in
            Task { @MainActor in self?.listenerState = s }
        }
        server.onStats = { [weak self] s in
            Task { @MainActor in
                self?.stats = s
                if let c = self?.capture { self?.leveler = c.levelerTelemetry }
            }
        }
        capture.requestAccess { [weak self] ok in
            guard let self else { return }
            self.cameraDenied = !ok
            self.server.start()
        }
    }

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @AppStorage("horizonLeveling") private var horizonLeveling = true

    var body: some View {
        HStack(spacing: 0) {
            CameraPreview(session: model.capture.session) { layer in
                model.capture.previewLayer = layer
            }
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("iPhone USB Camera").font(.headline)

                statusLine

                if model.cameraDenied {
                    Text("Kamerazugriff verweigert. In den Einstellungen erlauben.")
                        .font(.footnote).foregroundStyle(.red)
                }

                Picker("Kamera", selection: $model.selectedCameraId) {
                    ForEach(model.cameras, id: \.id) { c in
                        Text(c.name).tag(c.id)
                    }
                }
                .pickerStyle(.inline)
                .frame(maxHeight: 160)

                Toggle("Bildschirm an lassen", isOn: $model.keepScreenOn)

                Toggle("Auto-Rotation", isOn: $model.autoRotation)

                Toggle("Horizont begradigen", isOn: $horizonLeveling)
                    .disabled(!model.autoRotation)

                OrientationRow(sensor: model.capture.orientation,
                               leveler: model.leveler,
                               levelingOn: horizonLeveling && model.autoRotation)

                if !model.autoRotation {
                    Picker("Drehung", selection: $model.manualRotation) {
                        ForEach([0, 90, 180, 270], id: \.self) { a in
                            Text("\(a)°").tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Spacer()
                Text("Port \(Int(Iucm.defaultPort)) - Kamera per USB-Kabel")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 280)
            .background(.thinMaterial)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            model.horizonLeveling = horizonLeveling
            model.boot()
        }
        .onChange(of: horizonLeveling) { _, on in model.horizonLeveling = on }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Listener", model.listenerState)
            row("Verbunden", model.stats.connected ? "ja" : "nein")
            row("Streamt", model.stats.streaming ? "ja" : "nein")
            row("fps", String(format: "%.1f", model.stats.fps))
            row("kbit/s", String(format: "%.0f", model.stats.kbps))
        }
        .font(.system(.footnote, design: .monospaced))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v)
        }
    }
}

/// Tripod diagnostics: quantised angle, confidence (in-plane gravity magnitude)
/// and the raw continuous angle, so the orientation can be verified on site
/// without a console attached.
struct OrientationRow: View {
    @ObservedObject var sensor: OrientationSensor
    var leveler = HorizonLeveler.Telemetry()
    var levelingOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "Lage: %.0f\u{00B0} (m=%.2f)",
                        Double(sensor.captureAngle), Double(sensor.confidence)))
            Text(String(format: "roh %.0f\u{00B0}%@",
                        Double(sensor.continuousAngle),
                        sensor.confidence < OrientationMath.flatThreshold ? "  flach - haelt" : ""))
                .foregroundStyle(.secondary)
            if levelingOn {
                Text(String(format: "Rest %+.1f\u{00B0}  %.1f ms  drop %d",
                            Double(leveler.lastResidualDeg), leveler.avgMs,
                            leveler.droppedFrames))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption2, design: .monospaced))
    }
}
