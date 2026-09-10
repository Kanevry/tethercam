// OnboardingWindow.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer
//
// The setup guide: four steps with live checkmarks, shown on first launch and
// whenever the camera extension is not approved (OnboardingPolicy).
//
// All user-facing strings are English literals collected in `Strings` below —
// one place to lift into a .strings catalogue once localization arrives.

import SwiftUI
import TetherCamCore

/// Every sentence the setup guide shows. Kept in one enum so a later
/// `NSLocalizedString` pass touches this file only.
enum OnboardingStrings {
    static let title = "Set up TetherCam"
    static let subtitle = "Your iPhone becomes a camera in every Mac app — over the cable, no Wi-Fi."

    static let step1Title = "Move TetherCam to the Applications folder"
    static let step1Body = "macOS installs the camera extension only from /Applications. "
        + "Drag the app there with Finder, then open it again."
    static let step1Done = "TetherCam runs from /Applications."

    static let step2Title = "Approve the camera extension"
    static let step2Body = "System Settings > General > Login Items & Extensions > Camera Extensions: "
        + "switch TetherCam on. macOS asks for an admin password — that is the system's approval, "
        + "not something TetherCam can do for you."
    static let step2Done = "The camera extension is approved and running."
    static let step2Button = "Open System Settings"

    static let step3Title = "Connect the iPhone"
    static let step3Body = "Install TetherCam from the App Store on the iPhone, connect it with the cable "
        + "and tap Trust on the phone. Keep the app in the foreground — iOS suspends it otherwise."
    static let step3Link = "TetherCam on the App Store"
    static let step3URL = URL(string: "https://apps.apple.com/us/app/tethercam/id6808997521")!

    static let step4Title = "Pick \"TetherCam\" as the camera"
    static let step4Body = "In Zoom, Teams, Meet, FaceTime or any other app choose the camera named "
        + "\"TetherCam\". Apps read the camera list at launch: quit and reopen an app that was already "
        + "running before the extension appeared."

    static let noteAudio = "The virtual camera carries no audio. For sound from the phone use the "
        + "TetherCam OBS plugin."
    static let noteSingleReceiver = "Do not run the OBS plugin at the same time: the phone accepts one "
        + "receiver, the second one gets BUSY."

    static let done = "Done"
    static let menuItem = "Setup guide…"
}

/// One numbered step with a live checkmark.
private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    let text: String
    /// nil = the step has no automatic check (the user decides).
    let isDone: Bool?
    let doneText: String?
    @ViewBuilder let accessory: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(isDone == true ? Color.green : Color.secondary)
                .font(.title3)
                .accessibilityLabel(isDone == true ? "done" : "step \(number)")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(isDone == true ? (doneText ?? text) : text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        if isDone == true { return "checkmark.circle.fill" }
        return "\(number).circle"
    }
}

struct OnboardingWindow: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(OnboardingStrings.title).font(.title2).bold()
                    Text(OnboardingStrings.subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StepRow(number: 1, title: OnboardingStrings.step1Title,
                        text: OnboardingStrings.step1Body,
                        isDone: state.isInApplicationsFolder,
                        doneText: OnboardingStrings.step1Done) { EmptyView() }

                StepRow(number: 2, title: OnboardingStrings.step2Title,
                        text: OnboardingStrings.step2Body,
                        isDone: state.extensionState == .enabled,
                        doneText: OnboardingStrings.step2Done) {
                    HStack(spacing: 8) {
                        Button(OnboardingStrings.step2Button) { state.openExtensionSettings() }
                        Text(state.extensionState.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                StepRow(number: 3, title: OnboardingStrings.step3Title,
                        text: OnboardingStrings.step3Body,
                        isDone: state.status.link == .streaming,
                        doneText: OnboardingStrings.step3Body) {
                    Link(OnboardingStrings.step3Link, destination: OnboardingStrings.step3URL)
                        .font(.callout)
                        .padding(.top, 2)
                }

                StepRow(number: 4, title: OnboardingStrings.step4Title,
                        text: OnboardingStrings.step4Body,
                        isDone: nil, doneText: nil) { EmptyView() }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label(OnboardingStrings.noteAudio, systemImage: "speaker.slash")
                    Label(OnboardingStrings.noteSingleReceiver, systemImage: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button(OnboardingStrings.done) { state.completeOnboarding() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

/// Hosts `OnboardingWindow` in a plain `NSWindow`.
///
/// A SwiftUI `Window` scene cannot be opened before a view tree exists (the
/// `openWindow` action lives in the environment), and an LSUIElement menu-bar
/// app has no view tree until the user clicks the menu — exactly the moment the
/// first-run guide must NOT wait for. So the guide is AppKit-hosted.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    /// Creates the window on first use and brings it to the front afterwards.
    func present(state: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingWindow().environmentObject(state))
            let w = NSWindow(contentViewController: hosting)
            w.title = OnboardingStrings.title
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}
