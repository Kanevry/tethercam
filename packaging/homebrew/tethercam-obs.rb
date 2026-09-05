# Homebrew cask for the TetherCam OBS plugin. DRAFT, not published to any tap.
#
# `version` and `sha256` are filled by the release job; the checksum is the one
# published next to the asset as TetherCam-obs-plugin.pkg.sha256.
# See packaging/homebrew/README.md for the open point about the install domain.
cask "tethercam-obs" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Kanevry/tethercam/releases/download/v#{version}/TetherCam-obs-plugin.pkg",
      verified: "github.com/Kanevry/tethercam/"
  name "TetherCam for OBS"
  desc "OBS source plugin for an iPhone camera over the USB cable"
  homepage "https://github.com/Kanevry/tethercam"

  # VideoToolbox HEVC decode plus the plugin's deployment target.
  depends_on macos: ">= :monterey"

  pkg "TetherCam-obs-plugin.pkg"

  uninstall pkgutil: "at.gotzendorfer.obs-iphone-usb-cam"

  # The plugin keeps one small file: the once-per-scene-collection flag for the
  # first-run hint. Nothing else is written outside the plugin bundle.
  zap trash: [
    "~/Library/Application Support/obs-studio/plugin_config/obs-iphone-usb-cam",
  ]

  caveats do
    "Restart OBS after installing, then use Tools -> \"TetherCam: Add iPhone camera to current scene\"."
  end
end
