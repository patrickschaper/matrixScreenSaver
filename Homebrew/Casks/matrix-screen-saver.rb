cask "matrix-screen-saver" do
  version "0.2.0"
  sha256 "7a60c8ec2855a2df4cb008da7f79ea9e8526385897e3048bb53bb42421e07acd"

  url "https://github.com/patrickschaper/matrixScreenSaver/releases/download/#{version}/#{version}.zip"
  name "MatrixScreenSaver"
  desc "Native terminal-style Matrix screen saver"
  homepage "https://github.com/patrickschaper/matrixScreenSaver"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  screen_saver "MatrixScreenSaver.saver"

  # Staging writes a receipt before preflight; querying there misclassifies fresh installs.
  previously_managed = @cask.installed?

  # Conditional initial-only setup has no equivalent declarative install step in Homebrew 7.0.7.
  # rubocop:disable Cask/InstallSteps
  preflight do
    saver = cask.artifacts.find { |artifact| artifact.is_a?(Cask::Artifact::ScreenSaver) }
    if !previously_managed && (saver.target.exist? || saver.target.symlink?)
      opoo "Existing screen saver at #{saver.target}. To replace it while retaining options, run: " \
           "brew install --cask --force #{cask.full_name}"
    end

    raise "Missing staged screen saver: #{saver.source}" unless saver.source.directory?

    ohai "Removing staged quarantine bypasses Gatekeeper quarantine checks; " \
         "this does not make the saver notarized or Apple-approved."
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", saver.source.to_s]
  end

  postflight do
    ohai "There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82"
    unless previously_managed
      ohai "Select MatrixScreenSaver in System Settings > Wallpaper > Screen Saver."
      begin
        system_command "/usr/bin/open",
                       args: ["x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"]
      rescue StandardError
        opoo "Could not open settings. Open System Settings > Wallpaper > Screen Saver and select MatrixScreenSaver."
      end
    end
  end
  # rubocop:enable Cask/InstallSteps
end
