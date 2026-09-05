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

    let capture = CaptureEngine()
    private lazy var server = UsbServer(capture: capture)

    var cameras: [CameraDescriptor] { capture.descriptors }

    func boot() {
        applyIdleTimer()
        server.onListenerState = { [weak self] s in
            Task { @MainActor in self?.listenerState = s }
        }
        server.onStats = { [weak self] s in
            Task { @MainActor in self?.stats = s }
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

    var body: some View {
        HStack(spacing: 0) {
            CameraPreview(session: model.capture.session)
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

                Spacer()
                Text("Port \(Int(Iucm.defaultPort)) - Kamera per USB-Kabel")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 280)
            .background(.thinMaterial)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { model.boot() }
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
