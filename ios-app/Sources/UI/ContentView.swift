import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    /// What the single status line says. Nothing else is shown on the main
    /// screen, so this enum is the whole main-screen state.
    enum Link {
        case waiting
        case connected
        case streaming
    }

    @Published var listenerState = ""
    @Published var stats = UsbServer.Stats()
    @Published var selectedCameraId: UInt8 = 0
    @Published var cameraDenied = false
    /// Refreshed once per second from the server tick — no extra timer.
    @Published var leveler = HorizonLeveler.Telemetry()

    /// Defaults that are not offered as main-screen switches: the phone hangs in
    /// a mount whose orientation the app cannot know, so levelling on is the only
    /// answer that is right without being told. All three live under "Advanced".
    @Published var autoRotation = true { didSet { capture.autoRotation = autoRotation } }
    @Published var horizonLeveling = true { didSet { capture.horizonLeveling = horizonLeveling } }
    @Published var manualRotation: Int = 0 {
        didSet { capture.manualRotationAngle = CGFloat(manualRotation) }
    }

    let capture = CaptureEngine()
    private lazy var server = UsbServer(capture: capture)
    private var started = false

    var cameras: [CameraDescriptor] { capture.descriptors }

    var link: Link {
        if stats.streaming && stats.width > 0 { return .streaming }
        return stats.connected ? .connected : .waiting
    }

    /// "1080p30" — the shorthand a streamer reads at a glance.
    var formatLabel: String {
        stats.width > 0 ? "\(stats.height)p\(stats.targetFps)" : ""
    }

    func boot() {
        // Always on: a phone that sleeps mid-stream is the single most common
        // way this setup fails, and there is no case where sleeping is wanted.
        UIApplication.shared.isIdleTimerDisabled = true
        guard !started else { return }
        started = true
        server.onListenerState = { [weak self] s in
            Task { @MainActor in self?.listenerState = s }
        }
        server.onStats = { [weak self] s in
            Task { @MainActor in
                self?.stats = s
                if let c = self?.capture { self?.leveler = c.levelerTelemetry }
            }
        }
        // Straight to the system alert. The purpose string in Info.plist is the
        // explanation; a separate onboarding page in front of it only adds a tap.
        capture.requestAccess { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                self.cameraDenied = !ok
                if ok { self.server.start() }
            }
        }
    }

    /// The phone's lens choice. Goes through the server so a running stream is
    /// restarted with the new camera and the same format; while nothing streams
    /// it is only remembered and applied to the next START.
    func selectCamera(_ id: UInt8) {
        guard capture.cameras.contains(where: { $0.id == id }) else { return }
        selectedCameraId = id
        server.selectCamera(id)
    }

    func refreshPermission() {
        cameraDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @AppStorage("horizonLeveling") private var horizonLeveling = true
    /// Back wide (id 0) is the default: it is the lens a phone in a mount is
    /// pointed with unless someone says otherwise.
    @AppStorage("preferredCameraId") private var preferredCameraId = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showForegroundBanner = false
    @State private var wasBackgrounded = false

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreview(session: model.capture.session) { layer in
                model.capture.previewLayer = layer
            }
            .background(Color.black)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    StatusPill(link: model.link, format: model.formatLabel)
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.45)))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(Text("settings.title"))
                }

                // One sentence, and only while nothing has connected yet.
                if model.link == .waiting && !model.cameraDenied {
                    OverlayText(key: "hint.firstRun")
                }
                if model.cameraDenied {
                    PermissionDeniedCard(onOpenSettings: { model.openSystemSettings() })
                }
                if showForegroundBanner {
                    OverlayText(key: "banner.foreground", tint: .orange)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .statusBarHidden(true)
        .onAppear {
            model.horizonLeveling = horizonLeveling
            model.boot()
            model.selectCamera(UInt8(clamping: preferredCameraId))
        }
        .onChange(of: horizonLeveling) { _, on in model.horizonLeveling = on }
        .onChange(of: preferredCameraId) { _, id in model.selectCamera(UInt8(clamping: id)) }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model, horizonLeveling: $horizonLeveling,
                          preferredCameraId: $preferredCameraId)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasBackgrounded = true
        case .active:
            model.refreshPermission()
            guard wasBackgrounded else { return }
            wasBackgrounded = false
            withAnimation { showForegroundBanner = true }
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                withAnimation { showForegroundBanner = false }
            }
        default:
            break
        }
    }
}

/// The whole main-screen UI: a dot and a sentence.
struct StatusPill: View {
    let link: AppModel.Link
    let format: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            text.font(.footnote.weight(.medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    private var text: Text {
        switch link {
        case .waiting: return Text("status.waiting")
        case .connected: return Text("status.connected")
        case .streaming:
            return Text(String(format: String(localized: "status.streaming"), format))
        }
    }

    /// Traffic light, and never red: waiting for the Mac is not a fault.
    private var color: Color {
        switch link {
        case .waiting: return .orange
        case .connected: return .yellow
        case .streaming: return .green
        }
    }
}

struct OverlayText: View {
    let key: LocalizedStringKey
    var tint: Color = .white

    var body: some View {
        Text(key)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.45)))
    }
}

struct PermissionDeniedCard: View {
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("perm.denied.title").font(.footnote.weight(.semibold))
                Text("perm.denied.body").font(.caption2)
            }
            Button(action: onOpenSettings) {
                Text("perm.openSettings").font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.75)))
    }
}

/// Everything that is not the picture. Camera choice first, because that is the
/// only setting most people ever touch; the rest is folded away.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Binding var horizonLeveling: Bool
    @Binding var preferredCameraId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showAdvanced = false
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack {
            List {
                Section("settings.camera") {
                    // Plain rows with a checkmark instead of a Picker: the popup
                    // menu variant becomes unreadable once four lenses are listed.
                    ForEach(model.cameras, id: \.id) { c in
                        Button {
                            // Persist first; the onChange in ContentView is what
                            // restarts a running capture on the new lens.
                            preferredCameraId = Int(c.id)
                        } label: {
                            HStack {
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                if model.selectedCameraId == c.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    DisclosureGroup("settings.advanced", isExpanded: $showAdvanced) {
                        Toggle("settings.autoRotation", isOn: $model.autoRotation)
                        Toggle("settings.horizonLeveling", isOn: $horizonLeveling)
                            .disabled(!model.autoRotation)
                        if !model.autoRotation {
                            Picker("settings.manualAngle", selection: $model.manualRotation) {
                                ForEach([0, 90, 180, 270], id: \.self) { a in
                                    Text("\(a)\u{00B0}").tag(a)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                Section {
                    DisclosureGroup("settings.diagnostics", isExpanded: $showDiagnostics) {
                        diagRow("diag.listener", model.listenerState)
                        diagRow("diag.connected", yesNo(model.stats.connected))
                        diagRow("diag.streaming", yesNo(model.stats.streaming))
                        diagRow("diag.fps", String(format: "%.1f", model.stats.fps))
                        diagRow("diag.kbps", String(format: "%.0f", model.stats.kbps))
                        diagRow("diag.port", "\(Int(Iucm.defaultPort))")
                        diagRow("diag.angle", String(format: "%.0f\u{00B0} (m=%.2f)",
                                                    Double(model.capture.orientation.captureAngle),
                                                    Double(model.capture.orientation.confidence)))
                        diagRow("diag.residual", String(format: "%+.1f\u{00B0}  %.1f ms  drop %d",
                                                        Double(model.leveler.lastResidualDeg),
                                                        model.leveler.avgMs,
                                                        model.leveler.droppedFrames))
                    }
                }

                Section {
                    Link(destination: URL(string: "https://github.com/Kanevry/tethercam#quick-start")!) {
                        Label("link.installPlugin", systemImage: "arrow.down.circle")
                    }
                }
            }
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") { dismiss() }
                }
            }
        }
    }

    private func yesNo(_ b: Bool) -> String {
        String(localized: b ? "diag.yes" : "diag.no")
    }

    private func diagRow(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(.caption, design: .monospaced))
    }
}
