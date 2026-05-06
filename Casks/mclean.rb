cask "mclean" do
  version "1.0.0"
  sha256 "3d120e68ec453dc6099970b1333787c4676dea6e1007c8d5d474151c46974c0c"

  url "https://github.com/Engagendy/mclean/releases/download/v#{version}/MClean-#{version}-arm64.dmg",
      verified: "github.com/Engagendy/mclean/"

  name "MClean"
  desc "Native macOS cleanup scanner for cache, temporary, old, and large files"
  homepage "https://github.com/Engagendy/mclean"

  depends_on macos: ">= :sonoma"

  app "MClean.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/MClean.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Caches/com.engagendy.MClean",
    "~/Library/Preferences/com.engagendy.MClean.plist",
    "~/Library/Saved Application State/com.engagendy.MClean.savedState",
  ]
end
