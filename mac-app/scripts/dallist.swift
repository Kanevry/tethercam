// dallist.swift: list cameras through the legacy CoreMediaIO DAL API (uid, model, transport, streams, formats).
// Build: swiftc -O -o /tmp/dallist mac-app/scripts/dallist.swift && /tmp/dallist
// SPDX-License-Identifier: MIT
import CoreMediaIO
import CoreMedia
import Foundation
func prop(_ obj: CMIOObjectID, _ sel: CMIOObjectPropertySelector, _ scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> [UInt8]? {
  var addr = CMIOObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  guard CMIOObjectHasProperty(obj, &addr) else { return nil }
  var size: UInt32 = 0
  guard CMIOObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == 0, size > 0 else { return nil }
  var buf = [UInt8](repeating: 0, count: Int(size)); var used: UInt32 = 0
  guard CMIOObjectGetPropertyData(obj, &addr, 0, nil, size, &used, &buf) == 0 else { return nil }
  return buf
}
func cfstr(_ obj: CMIOObjectID, _ sel: CMIOObjectPropertySelector) -> String {
  guard let b = prop(obj, sel) else { return "-" }
  let u = b.withUnsafeBytes { $0.load(as: Unmanaged<CFString>.self) }
  return u.takeUnretainedValue() as String
}
func u32(_ obj: CMIOObjectID, _ sel: CMIOObjectPropertySelector) -> UInt32 { prop(obj, sel).map { $0.withUnsafeBytes { $0.load(as: UInt32.self) } } ?? 0 }
func fourcc(_ v: UInt32) -> String { String(bytes: [UInt8(v>>24&255),UInt8(v>>16&255),UInt8(v>>8&255),UInt8(v&255)], encoding: .ascii) ?? "?" }
guard let devs = prop(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)) else { print("no devices prop"); exit(1) }
let ids = devs.withUnsafeBytes { Array($0.bindMemory(to: CMIOObjectID.self)) }
for d in ids {
  let name = cfstr(d, CMIOObjectPropertySelector(kCMIOObjectPropertyName))
  let uid = cfstr(d, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID))
  let model = cfstr(d, CMIOObjectPropertySelector(kCMIODevicePropertyModelUID))
  let transport = u32(d, CMIOObjectPropertySelector(kCMIODevicePropertyTransportType))
  let alive = u32(d, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsAlive))
  let running = u32(d, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
  let hog = u32(d, CMIOObjectPropertySelector(kCMIODevicePropertyHogMode))
  print("dev \(d) name=\(name) uid=\(uid) model=\(model) transport=\(fourcc(transport)) alive=\(alive) runningSomewhere=\(running) hog=\(hog)")
  if let s = prop(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput)) {
    let sids = s.withUnsafeBytes { Array($0.bindMemory(to: CMIOStreamID.self)) }
    for sid in sids {
      let dir = u32(sid, CMIOObjectPropertySelector(kCMIOStreamPropertyDirection))
      let sname = cfstr(sid, CMIOObjectPropertySelector(kCMIOObjectPropertyName))
      var n = 0; var fmts = ""
      if let f = prop(sid, CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescriptions)) {
        let arr = f.withUnsafeBytes { $0.load(as: Unmanaged<CFArray>.self) }.takeUnretainedValue() as! [CMFormatDescription]
        n = arr.count
        for fd in arr.prefix(4) { let dim = CMVideoFormatDescriptionGetDimensions(fd); fmts += " \(fourcc(CMFormatDescriptionGetMediaSubType(fd)))\(dim.width)x\(dim.height)" }
      }
      print("   stream \(sid) dir=\(dir) name=\(sname) formats=\(n):\(fmts)")
    }
  }
  if let s = prop(d, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), CMIOObjectPropertyScope(kCMIODevicePropertyScopeOutput)) {
    let sids = s.withUnsafeBytes { Array($0.bindMemory(to: CMIOStreamID.self)) }
    print("   output streams: \(sids.count)")
  }
}
