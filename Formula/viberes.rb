# Homebrew formula for the `viberes` CLI companion. Builds the binary from
# source — no notarization or pre-built artifact required.
#
# Install with:
#   brew install m-moravcik/VibeRes/viberes
#
# Or, if you've already tapped this repo:
#   brew tap m-moravcik/viberes https://github.com/m-moravcik/VibeRes.git
#   brew install viberes
class Viberes < Formula
  desc "Command-line companion for VibeRes (macOS resolution switcher)"
  homepage "https://github.com/m-moravcik/VibeRes"
  url "https://github.com/m-moravcik/VibeRes.git", tag: "v0.4.1", revision: nil
  version "0.4.1"
  license "MIT"
  head "https://github.com/m-moravcik/VibeRes.git", branch: "main"

  depends_on xcode: ["26.0", :build]
  depends_on "xcodegen" => :build
  depends_on macos: :tahoe

  def install
    system "xcodegen", "generate"
    system "xcodebuild",
           "-project", "VibeRes.xcodeproj",
           "-scheme", "viberes-cli",
           "-configuration", "Release",
           "-derivedDataPath", "build",
           "CODE_SIGN_IDENTITY=-",
           "CODE_SIGNING_REQUIRED=NO",
           "build"

    bin.install "build/Build/Products/Release/viberes"
  end

  test do
    # Smoke-test that the binary runs and prints its help banner.
    # We avoid `viberes set` here because that mutates display state.
    assert_match "viberes", shell_output("#{bin}/viberes help")
  end
end
