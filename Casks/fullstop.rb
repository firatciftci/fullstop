cask "fullstop" do
  version :latest
  sha256 :no_check

  url "https://github.com/firatciftci/fullstop/releases/latest/download/Fullstop.dmg"
  name "Fullstop"
  desc "Menu bar battery charge limiter for Apple Silicon Macs"
  homepage "https://github.com/firatciftci/fullstop"

  auto_updates true
  depends_on arch: :arm64

  app "Fullstop.app"

  uninstall quit:      "com.firatciftci.Fullstop",
            launchctl: "com.firatciftci.Fullstop.helper"

  zap trash: [
    "~/Library/Application Support/Fullstop",
    "~/Library/Caches/com.firatciftci.Fullstop",
    "~/Library/HTTPStorages/com.firatciftci.Fullstop",
    "~/Library/Preferences/com.firatciftci.Fullstop.plist",
  ]
end
