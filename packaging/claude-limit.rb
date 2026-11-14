cask "claude-limit" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_ZIP"

  url "https://github.com/tfiechowski/claude-limit/releases/download/v#{version}/ClaudeLimit-#{version}-macOS.zip"
  name "ClaudeLimit"
  desc "Menu-bar display of Claude Code usage limits (unofficial)"
  homepage "https://github.com/tfiechowski/claude-limit"

  depends_on macos: ">= :ventura"

  app "ClaudeLimit.app"

  zap trash: "~/Library/Preferences/dev.tfi.claudelimit.plist"
end
