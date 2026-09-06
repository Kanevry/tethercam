# Homebrew cask for the TetherCam OBS plugin. Published to the personal tap
# Kanevry/homebrew-tethercam (brew tap kanevry/tethercam) as Casks/tethercam-obs.rb;
# see docs/listings/homebrew-decision.md for why a personal tap and not homebrew/cask
# (repo too new and too small for a self-submission there).
#
# Shape: zip + artifact, not pkg. The pkg's install domain only enables
# currentUserHome (packaging/distribution.xml.in), so `brew install --cask` running
# `installer -pkg ... -target /` would be refused; the zip sidesteps that by having
# Homebrew copy the plugin bundle into the user's own home itself, same as
# scripts/install.sh does by hand.
#
# `version` and `sha256` are bumped by hand on each release (see the tap README);
# the checksum below is the one published next to the v0.1.0 zip asset as
# TetherCam-obs-plugin.zip.sha256, verified 2026-09-06 against a fresh download.
cask "tethercam-obs" do
  version "0.1.0"
  sha256 "ff7106f81a8ae85f86df2c56621ecaf43507b9c71582a62f868418fcd287679d"

  url "https://github.com/Kanevry/tethercam/releases/download/v#{version}/TetherCam-obs-plugin.zip"
  name "TetherCam for OBS"
  desc "OBS source plugin for an iPhone camera over the USB cable"
  homepage "https://github.com/Kanevry/tethercam"

  # VideoToolbox HEVC decode plus the plugin's deployment target.
  depends_on macos: :monterey

  # The zip's top-level entry is the bundle itself: packaging/build-pkg.sh builds it
  # with `ditto --keepParent`, which keeps only the bundle's own directory name, not a
  # wrapping "TetherCam-obs-plugin" folder (verified 2026-09-05 against that script and
  # a local ditto --keepParent test).
  artifact "obs-iphone-usb-cam.plugin",
           target: "#{Dir.home}/Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin"

  # The plugin keeps one small file: the once-per-scene-collection flag for the
  # first-run hint. Nothing else is written outside the plugin bundle.
  zap trash: "~/Library/Application Support/obs-studio/plugin_config/obs-iphone-usb-cam"

  caveats do
    "Restart OBS after installing, then use Tools -> \"TetherCam: Add iPhone camera to current scene\"."
  end
end
