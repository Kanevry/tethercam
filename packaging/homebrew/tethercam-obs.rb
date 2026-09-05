# Homebrew cask for the TetherCam OBS plugin. DRAFT, not published to any tap; see
# docs/listings/homebrew-decision.md for why (repo too new and too small for
# homebrew/cask, and no personal tap exists yet).
#
# Shape: zip + artifact, not pkg. The pkg's install domain only enables
# currentUserHome (packaging/distribution.xml.in), so `brew install --cask` running
# `installer -pkg ... -target /` would be refused; the zip sidesteps that by having
# Homebrew copy the plugin bundle into the user's own home itself, same as
# scripts/install.sh does by hand.
#
# `version` and `sha256` are filled by the release job; the checksum is the one
# published next to the zip asset as TetherCam-obs-plugin.zip.sha256.
cask "tethercam-obs" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER: not a real checksum, replace from TetherCam-obs-plugin.zip.sha256

  url "https://github.com/Kanevry/tethercam/releases/download/v#{version}/TetherCam-obs-plugin.zip",
      verified: "github.com/Kanevry/tethercam/"
  name "TetherCam for OBS"
  desc "OBS source plugin for an iPhone camera over the USB cable"
  homepage "https://github.com/Kanevry/tethercam"

  # VideoToolbox HEVC decode plus the plugin's deployment target.
  depends_on macos: ">= :monterey"

  # The zip's top-level entry is the bundle itself: packaging/build-pkg.sh builds it
  # with `ditto --keepParent`, which keeps only the bundle's own directory name, not a
  # wrapping "TetherCam-obs-plugin" folder (verified 2026-09-05 against that script and
  # a local ditto --keepParent test).
  artifact "obs-iphone-usb-cam.plugin",
           target: "#{Dir.home}/Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin"

  # The plugin keeps one small file: the once-per-scene-collection flag for the
  # first-run hint. Nothing else is written outside the plugin bundle.
  zap trash: [
    "~/Library/Application Support/obs-studio/plugin_config/obs-iphone-usb-cam",
  ]

  caveats do
    "Restart OBS after installing, then use Tools -> \"TetherCam: Add iPhone camera to current scene\"."
  end
end
