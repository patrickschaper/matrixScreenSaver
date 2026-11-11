cask "matrix-screen-saver" do
  version "0.2.0"
  sha256 "7a60c8ec2855a2df4cb008da7f79ea9e8526385897e3048bb53bb42421e07acd"

  url "https://github.com/patrickschaper/matrixScreenSaver/releases/download/#{version}/#{version}.zip"
  name "MatrixScreenSaver"
  desc "Native terminal-style Matrix screen saver and wallpaper"
  homepage "https://github.com/patrickschaper/matrixScreenSaver"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "MatrixWallpaper.app", target: "Matrix Wallpaper.app"
  screen_saver "MatrixScreenSaver.saver"

  # These configured paths are not supported as install-step template tokens.
  saver_destination = "#{self.cask.config.screen_saverdir}/MatrixScreenSaver.saver"
  user_home = Dir.home

  preflight_steps do
    run "/bin/bash",
        args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "validate",
               "{{staged_path}}/MatrixWallpaper.app", "{{staged_path}}/MatrixScreenSaver.saver"],
        env: { "HOME" => user_home }
    run "/bin/bash",
        args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "suspend",
               "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
        env: { "HOME" => user_home },
        writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                         "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"]
    if_path_exists "MatrixScreenSaver.saver", base: :screen_saverdir do
      # Homebrew also grants read access here when the native target is under HOME.
      run "/bin/echo",
          args:           ["Existing screen saver in Homebrew's configured screen-saver directory. " \
                           "To replace it while retaining options, run: " \
                           "brew install --cask --force patrickschaper/tap/matrix-screen-saver"],
          print_stdout:   true,
          writable_paths: [{ path: "MatrixScreenSaver.saver", base: :screen_saverdir }]
    end

    if_path_exists "Matrix Wallpaper.app", base: :appdir do
      run "/bin/echo",
          args:           ["Existing app at {{appdir}}/Matrix Wallpaper.app. " \
                           "To replace it while retaining options, run: " \
                           "brew install --cask --force patrickschaper/tap/matrix-screen-saver"],
          print_stdout:   true,
          writable_paths: [{ path: "Matrix Wallpaper.app", base: :appdir }]
    end

    run "/bin/echo",
        args:         ["Removing staged quarantine bypasses Gatekeeper quarantine checks; " \
                       "this does not make either bundle notarized or Apple-approved."],
        print_stdout: true
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{staged_path}}/MatrixScreenSaver.saver"],
        writable_paths: ["{{staged_path}}/MatrixScreenSaver.saver"]
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{staged_path}}/MatrixWallpaper.app"],
        writable_paths: ["{{staged_path}}/MatrixWallpaper.app"]
  end

  postflight_steps do
    run "/bin/bash",
        args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "register",
               "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
        env: { "HOME" => user_home },
        writable_paths: ["{{appdir}}/Matrix Wallpaper.app", saver_destination,
                         "#{user_home}/Library/Application Support/MatrixWallpaper",
                         "#{user_home}/Library/LaunchAgents"]
    run "/bin/echo",
        args:         ["There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82"],
        print_stdout: true
    run "/bin/echo",
        args:         ["Open System Settings > Wallpaper > Screen Saver and select MatrixScreenSaver."],
        print_stdout: true
    run "/bin/echo",
        args:         ["Open {{appdir}}/Matrix Wallpaper.app to start Matrix Wallpaper. " \
                       "Launch at Login is optional in its Matrix menu."],
        print_stdout: true
  end

  uninstall_preflight_steps do
    run "/bin/bash",
        args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "suspend",
               "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
        env: { "HOME" => user_home },
        writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                         "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"]
    run "/bin/bash",
        args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "unregister"],
        env: { "HOME" => user_home },
        writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                         "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"]
  end

  uninstall quit: "dev.patsch.MatrixWallpaper", login_item: "Matrix Wallpaper"
end
