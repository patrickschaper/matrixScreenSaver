cask "matrix-screen-saver" do |dsl|
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
  saver_destination = "#{dsl.cask.config.screen_saverdir}/MatrixScreenSaver.saver"
  user_home = Dir.home

  # Serialized steps retain configured paths that the block DSL cannot express as tokens.
  preflight_steps [
    { type: :run, command: "/bin/bash",
      args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "validate",
             "{{staged_path}}/MatrixWallpaper.app", "{{staged_path}}/MatrixScreenSaver.saver"],
      env: { "HOME" => user_home } },
    { type: :run, command: "/bin/bash",
      args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "suspend",
             "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
      env: { "HOME" => user_home },
      writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                       "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"] },
    { type: :run, command: "/bin/echo",
      args: ["➡️ Existing screen saver in Homebrew's configured screen-saver directory. " \
             "To replace it while retaining options, run: " \
             "brew install --cask --force patrickschaper/tap/matrix-screen-saver"],
      print_stdout: true,
      guards: [{ id: "saver-conflict", condition: "if_exists",
                 path: "MatrixScreenSaver.saver", base: :screen_saverdir }],
      writable_paths: [{ path: "MatrixScreenSaver.saver", base: :screen_saverdir }] },
    { type: :run, command: "/bin/echo",
      args: ["➡️ Existing app at {{appdir}}/Matrix Wallpaper.app. " \
             "To replace it while retaining options, run: " \
             "brew install --cask --force patrickschaper/tap/matrix-screen-saver"],
      print_stdout: true,
      guards: [{ id: "app-conflict", condition: "if_exists", path: "Matrix Wallpaper.app", base: :appdir }],
      writable_paths: [{ path: "Matrix Wallpaper.app", base: :appdir }] },
    { type: :run, command: "/bin/echo",
      args: ["➡️ Removing staged quarantine bypasses Gatekeeper quarantine checks; " \
             "this does not make either bundle notarized or Apple-approved."],
      print_stdout: true },
    { type: :run, command: "/usr/bin/xattr",
      args: ["-dr", "com.apple.quarantine", "{{staged_path}}/MatrixScreenSaver.saver"],
      writable_paths: ["{{staged_path}}/MatrixScreenSaver.saver"] },
    { type: :run, command: "/usr/bin/xattr",
      args: ["-dr", "com.apple.quarantine", "{{staged_path}}/MatrixWallpaper.app"],
      writable_paths: ["{{staged_path}}/MatrixWallpaper.app"] },
  ]

  postflight_steps [
    { type: :run, command: "/bin/bash",
      args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "register",
             "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
      env: { "HOME" => user_home },
      writable_paths: ["{{appdir}}/Matrix Wallpaper.app", saver_destination,
                       "#{user_home}/Library/Application Support/MatrixWallpaper",
                       "#{user_home}/Library/LaunchAgents"] },
    { type: :run, command: "/bin/echo",
      args: ["➡️ There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82"], print_stdout: true },
    { type: :run, command: "/bin/echo",
      args: ["➡️ Open System Settings > Wallpaper > Screen Saver and select MatrixScreenSaver."],
      print_stdout: true },
    { type: :run, command: "/bin/echo",
      args: ["➡️ Open {{appdir}}/Matrix Wallpaper.app to start Matrix Wallpaper. " \
             "Launch at Login is optional in its Matrix menu."], print_stdout: true },
  ]

  uninstall_preflight_steps [
    { type: :run, command: "/bin/bash",
      args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "suspend",
             "{{appdir}}/Matrix Wallpaper.app", saver_destination, "homebrew"],
      env: { "HOME" => user_home },
      writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                       "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"] },
    { type: :run, command: "/bin/bash",
      args: ["{{staged_path}}/Scripts/product-lifecycle.sh", "unregister", "homebrew"],
      env: { "HOME" => user_home },
      writable_paths: ["#{user_home}/Library/Application Support/MatrixWallpaper",
                       "#{user_home}/Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist"] },
  ]

  uninstall launchctl: "dev.patsch.MatrixWallpaper.cleanup",
            quit: "dev.patsch.MatrixWallpaper", login_item: "Matrix Wallpaper"
end
