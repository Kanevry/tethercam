import Foundation

/// Which sentence the UI says about the receiver on the other end of the cable.
///
/// Pure on purpose: the picture can be received by the TetherCam Mac app (the
/// default path, a virtual camera for Zoom, Teams, Meet, FaceTime) or by OBS with
/// the TetherCam plugin (the pro path, with audio). Saying "OBS" to someone who
/// runs the Mac app is wrong, so the choice is made from CLIENT_INFO
/// (`protocol/PROTOCOL.md` 4.11) and unit-tested without a socket.
enum ReceiverStatus {

    /// What to render in the status pill while connected but not yet streaming.
    ///
    /// `name` is non-nil only for the `%@` variant and carries the receiver's own
    /// wire string, which is never localised (it arrives in English).
    static func connected(for receiver: ReceiverInfo?) -> (key: String, name: String?) {
        guard let receiver else { return ("status.connected.generic", nil) }
        switch receiver.clientKind {
        case .macApp: return ("status.connected.macApp", nil)
        case .obsPlugin: return ("status.connected.obs", nil)
        case .tool, .unknown:
            let name = receiver.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? ("status.connected.generic", nil)
                                : ("status.connected.named", name)
        }
    }

    /// The footnote under the microphone section. The Mac app carries no audio (a
    /// CoreMediaIO camera extension has no audio stream), so promising audio there
    /// would send people looking for a sound that cannot arrive. With nobody
    /// connected the OBS text is the generic answer.
    static func audioFootnoteKey(for receiver: ReceiverInfo?) -> String {
        receiver?.clientKind == .macApp ? "settings.audioFootnote.macApp"
                                        : "settings.audioFootnote.obs"
    }

    /// "<name> <version>" for the diagnostics row, or an em dash for a receiver
    /// that predates protocol 1.2 and never identified itself.
    static func diagnosticsValue(for receiver: ReceiverInfo?) -> String {
        guard let receiver else { return "\u{2014}" }
        let parts = [receiver.name, receiver.version]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "\u{2014}" : parts.joined(separator: " ")
    }
}
