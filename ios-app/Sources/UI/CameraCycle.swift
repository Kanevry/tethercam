import Foundation

/// Lens cycling for the double-tap on the preview (GitLab #9): the next camera
/// in the order the app lists them, wrapping around at the end. Pure so it can
/// be tested without a capture session.
enum CameraCycle {
    /// The id after `current` in `ids`, wrapping around. `nil` when there is
    /// nothing to cycle to (empty list or a single lens). An unknown `current`
    /// starts over at the first entry, so a stale persisted id never dead-ends.
    static func next(after current: UInt8, in ids: [UInt8]) -> UInt8? {
        guard ids.count > 1 else { return nil }
        guard let index = ids.firstIndex(of: current) else { return ids[0] }
        return ids[(index + 1) % ids.count]
    }

    static func next(after current: UInt8, in cameras: [CameraDescriptor]) -> UInt8? {
        next(after: current, in: cameras.map(\.id))
    }
}
