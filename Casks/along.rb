cask "along" do
  version "0.7.1"
  sha256 "47e21ad2bb1b384250d527f423df1edd7bf3ad0296e9577b4539fa7cbaa128c1"

  url "https://github.com/sujalalmeida/Along/releases/download/v#{version}/Along-#{version}-apple-silicon.zip"
  name "Along"
  desc "Scrolling window manager"
  homepage "https://github.com/sujalalmeida/Along"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Along.app"

  uninstall quit: "io.tileme.app"

  zap trash: [
    "~/Library/Preferences/io.tileme.app.plist",
    "~/Library/Saved Application State/io.tileme.app.savedState",
  ]

  caveats <<~EOS
    Open Along from Applications and enable Accessibility in System Settings.
    This preview is not notarized. If macOS blocks it, use Open Anyway in
    System Settings > Privacy & Security if you trust the download.
    Quit Along before upgrading so it can restore your window positions.
  EOS
end
