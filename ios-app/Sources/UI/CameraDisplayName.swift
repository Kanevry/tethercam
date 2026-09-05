import Foundation

/// Localized display names for the camera list in Settings.
///
/// `CameraDescriptor.name` is a wire field: the plugin receives the English
/// literal from `CaptureEngine.discover()` and shows it verbatim in OBS, so it
/// must stay English (protocol/PROTOCOL.md). The UI maps that literal to a
/// `Localizable.strings` key here and falls back to the raw name for anything
/// unknown, so a new lens is never rendered as an empty row.
extension CameraDescriptor {
    /// Name to show in the app UI, localized when the wire name is known.
    var displayName: String {
        let key: String
        switch name {
        case "Back Wide": key = "camera.backWide"
        case "Back Ultra Wide": key = "camera.backUltraWide"
        case "Back Telephoto": key = "camera.backTelephoto"
        case "Front": key = "camera.front"
        default: return name
        }
        let localized = NSLocalizedString(key, comment: "camera display name")
        return localized == key ? name : localized
    }
}
