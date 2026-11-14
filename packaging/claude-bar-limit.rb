cask "claude-bar-limit" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_ZIP"

  url "https://github.com/tfiechowski/claude-bar-limit/releases/download/v#{version}/ClaudeBarLimit-#{version}-macOS.zip"
  name "ClaudeBarLimit"
  desc "Menu-bar display of Claude Code usage limits (unofficial)"
  homepage "https://github.com/tfiechowski/claude-bar-limit"

  depends_on macos: ">= :ventura"

  app "ClaudeBarLimit.app"

  zap trash: "~/Library/Preferences/dev.tfi.claudebarlimit.plist"
end
