cask "island" do
  version "0.1.0"
  sha256 "9b8e9226b212ae8d6561ad382c72abbae36ce77174ed29e82bd6c09be9dcc105"

  url "https://github.com/zzcan/island/releases/download/v#{version}/island.app.zip"
  name "island"
  desc "Dynamic-island style monitor for Claude Code sessions around the notch"
  homepage "https://github.com/zzcan/island"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "island.app"

  zap trash: "~/Library/Preferences/app.island.local.plist"

  caveats <<~EOS
    island is ad-hoc signed (no Apple Developer certificate), so Gatekeeper
    will block it when installed with quarantine. Install with:

      brew install --cask --no-quarantine island

    or clear the flag after install:

      xattr -dr com.apple.quarantine "#{appdir}/island.app"
  EOS
end
