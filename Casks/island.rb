cask "island" do
  version "0.1.1"
  sha256 "3fb2478e4de34783996998d9ee252e7148ef34a1d5c75c29d7beccb9261cd6f1"

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
