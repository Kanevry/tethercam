# Homebrew cask for the TetherCam Mac app (menu bar host + Camera Extension): the
# iPhone as the system camera "TetherCam" for Zoom, Meet, FaceTime, QuickTime, browsers.
# Published to the personal tap Kanevry/homebrew-tethercam (brew tap kanevry/tethercam).
# `version` and `sha256` are bumped by hand per release; the checksum is the one
# published next to the .dmg asset as TetherCam-mac.dmg.sha256.
cask "tethercam" do
  version "0.4.0"
  sha256 "06f0ed0c1158cc24a2e328d97d1bd4d54936d82e402a6f435ef9915bb9ac16ee"

  url "https://github.com/Kanevry/tethercam/releases/download/v#{version}/TetherCam-mac.dmg"
  name "TetherCam"
  desc "iPhone as a USB webcam for every Mac app (menu bar app + camera extension)"
  homepage "https://tethercam.app"

  # Camera extensions and the host's deployment target.
  depends_on macos: ">= :sonoma"

  app "TetherCam.app"

  # The extension can only be activated from /Applications and needs a one-time
  # approval in System Settings; the app asks for it on first launch.
  caveats <<~EOS
    Open TetherCam once, then allow the camera extension under
    System Settings > General > Login Items & Extensions > Camera Extensions.
    Pick the camera "TetherCam" in any app. Video only; audio comes via the OBS plugin.
  EOS

  uninstall quit: "at.gotzendorfer.tethercam.mac"
  zap trash: "~/Library/Group Containers/G3QZ66475M.at.gotzendorfer.tethercam"
end
