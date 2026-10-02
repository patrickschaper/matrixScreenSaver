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

  preflight_steps do
    if_path_exists "MatrixScreenSaver.saver", base: :screen_saverdir do
      # Homebrew also grants read access here when the native target is under HOME.
      run "/bin/echo",
          args:           ["Existing screen saver at {{screen_saverdir}}/MatrixScreenSaver.saver. " \
                           "To replace it while retaining options, run: " \
                           "brew install --cask --force patrickschaper/tap/matrix-screen-saver"],
          print_stdout:   true,
          writable_paths: [{ path: "MatrixScreenSaver.saver", base: :screen_saverdir }]
    end

    run "/bin/echo",
        args:         ["Removing staged quarantine bypasses Gatekeeper quarantine checks; " \
                       "this does not make the saver notarized or Apple-approved."],
        print_stdout: true
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{staged_path}}/MatrixScreenSaver.saver"],
        writable_paths: ["{{staged_path}}/MatrixScreenSaver.saver"]
  end

  postflight_steps do
    run "/bin/echo",
        args:         ["There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82"],
        print_stdout: true
    run "/bin/echo",
        args:         ["Open System Settings > Wallpaper > Screen Saver and select MatrixScreenSaver."],
        print_stdout: true
  end
end
