// camlist.swift: list cameras as AVFoundation sees them (device type, model, transport, formats).
// Build: swiftc -O -o /tmp/camlist mac-app/scripts/camlist.swift && /tmp/camlist
// SPDX-License-Identifier: MIT
import AVFoundation
let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
let s = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
for d in s.devices {
  print("name=\(d.localizedName) type=\(d.deviceType.rawValue) model=\(d.modelID) uid=\(d.uniqueID) transport=\(d.transportType) suspended=\(d.isSuspended) formats=\(d.formats.count)")
  for f in d.formats.prefix(3) { print("   fmt=\(f.formatDescription.mediaSubType) \(f.formatDescription.dimensions.width)x\(f.formatDescription.dimensions.height) fps=\(f.videoSupportedFrameRateRanges.map{ "\($0.minFrameRate)-\($0.maxFrameRate)" })") }
}
