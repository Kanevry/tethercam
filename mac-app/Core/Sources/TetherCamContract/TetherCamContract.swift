// TetherCamContract.swift
// TetherCam for macOS: constants shared by the host app and the Camera Extension.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer
//
// CONTRACT-LOCK: this file is the single source of truth for identifiers and the
// published camera format. Both targets compile it. Change it in one commit with
// both sides, never from one side alone.

import CoreMedia
import CoreVideo
import Foundation

public enum TetherCamContract {
    /// Team-scoped app group shared by host and extension. Also the
    /// CMIOExtensionMachServiceName (Info.plist of the extension).
    public static let appGroup = "G3QZ66475M.at.gotzendorfer.tethercam"
    public static let hostBundleID = "at.gotzendorfer.tethercam.mac"
    public static let extensionBundleID = "at.gotzendorfer.tethercam.mac.camera"

    /// Stable UUIDs so clients keep their device selection across updates.
    /// Device UID as seen by AVCaptureDevice.uniqueID / kCMIODevicePropertyDeviceUID.
    public static let deviceUID = "7E1A0B62-5C0D-4E2B-9F5B-2C1D4A8E7C01"
    public static let sourceStreamUID = "7E1A0B62-5C0D-4E2B-9F5B-2C1D4A8E7C02"
    public static let sinkStreamUID = "7E1A0B62-5C0D-4E2B-9F5B-2C1D4A8E7C03"

    /// Localized name shown in Zoom, Teams, FaceTime, ffmpeg -list_devices.
    public static let cameraName = "TetherCam"
    public static let modelName = "TetherCam Virtual Camera"

    /// The ONE published stream format (v1): 1920x1080, NV12 video range, 30 fps.
    /// The host scales/letterboxes every decoded geometry into this format.
    public static let width: Int32 = 1920
    public static let height: Int32 = 1080
    public static let fps: Int32 = 30
    public static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    public static var frameDuration: CMTime { CMTime(value: 1, timescale: fps) }

    /// Sink queue depth the extension advertises; the host drops the newest
    /// frame when the queue is full instead of blocking the receiver.
    public static let sinkQueueDepth: Int = 4

    /// Host command line contract used by tools/vcam-test.sh.
    public static let debugTCPFlag = "--debug-tcp"   // HOST:PORT, bypasses usbmuxd
    public static let headlessFlag = "--headless"    // no menu bar UI, log to stderr
}
