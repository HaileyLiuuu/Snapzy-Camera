cask "snapzy-camera" do
  version "1.30.0-beta.7"
  sha256 "c6cffc3ce7fa2338bb28b56fd0235a10a1918ee0223a440f60bd22a0a215a6eb"

  url "https://github.com/HaileyLiuuu/Snapzy-Camera/releases/download/snapzy-camera-v#{version}/Snapzy-Camera-v#{version}.dmg"
  name "Snapzy Camera"
  desc "Unofficial Snapzy fork with camera picture-in-picture screen recording"
  homepage "https://github.com/HaileyLiuuu/Snapzy-Camera"

  depends_on macos: :ventura

  app "Snapzy Camera.app"

  zap trash: [
    "~/Library/Application Support/Snapzy Camera",
    "~/Library/Caches/com.haileyliu.snapzy-camera",
    "~/Library/Preferences/com.haileyliu.snapzy-camera.plist",
  ]

  caveats <<~EOS
    Snapzy Camera is ad-hoc signed and not notarized by Apple.
    On first launch, macOS may block the app. To open it:
      Right-click Snapzy Camera.app -> Open -> Open
    Then grant Screen Recording, Camera, and Microphone permissions in System Settings.
  EOS
end
