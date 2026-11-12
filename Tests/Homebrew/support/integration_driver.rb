# Run through `brew ruby`; never through a brew install/uninstall command.
require "cask/cask_loader"
require "cask/installer"
require "cask/upgrade"
require "digest"
require "stringio"

ENV["HOMEBREW_DEVELOPER"] = "1"
ROOT = Pathname(ARGV.fetch(0)).realpath
raise "Unsafe test root" unless ROOT.basename.to_s.start_with?("matrix-homebrew-integration.")
raise "Homebrew 7.0.7 or newer is required for this compatibility test" if Version.new(HOMEBREW_VERSION) < Version.new("7.0.7")
raise "Cache escaped isolation" unless HOMEBREW_CACHE.realpath.to_s.start_with?("#{ROOT}/")
raise "Native checks require Homebrew's sandbox" unless Sandbox.use_for?("running cask artifact operations")

# Redirect Homebrew's in-process Caskroom and tap objects, not the host installation.
Cask::Caskroom.instance_variable_set(:@path, ROOT/"Caskroom")
TAP = Tap.fetch("matrix-fixture/homebrew-test")
TAP.instance_variable_set(:@path, ROOT/"tap")
(TAP.path/"Casks").mkpath
CONFIG = Cask::Config.new(explicit: Cask::Config::DEFAULT_DIRS.keys.to_h { |key| [key, ROOT/key.to_s] })
TARGET = CONFIG.screen_saverdir/"MatrixScreenSaver.saver"
APP_TARGET = CONFIG.appdir/"Matrix Wallpaper.app"
LEGACY_APP_TARGET = CONFIG.appdir/"MatrixWallpaper.app"
TARGETS = [TARGET, APP_TARGET].freeze
# Sandboxed cask hooks use real launchctl; only app-side activation uses mocked services.
FIXTURE_HOME = ROOT/"home"
FIXTURE_BIN = ROOT/"bin"
# Outside-sandbox service fixtures cannot affect the logged-in user's LaunchAgents.
FIXTURE_SERVICES = ROOT/"services"
FIXTURE_HOME.mkpath
FIXTURE_BIN.mkpath
FIXTURE_SERVICES.mkpath
(FIXTURE_BIN/"codesign").write("#!/bin/sh\nexit 0\n")
(FIXTURE_SERVICES/"launchctl").write(<<~SH)
  #!/bin/bash
  case "$1" in
    print) test -f "#{ROOT}/job";;
    bootstrap) touch "#{ROOT}/job";;
    bootout) rm -f "#{ROOT}/job";;
    *) exit 1;;
  esac
SH
(FIXTURE_BIN/"codesign").chmod(0755)
(FIXTURE_SERVICES/"launchctl").chmod(0755)
PREFS = ROOT/"preferences-sentinel"
PREFS.write("saved options\x00")
COFFEE = "There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82".freeze
check_source = Pathname("Homebrew/Casks/matrix-screen-saver.rb").read
raise "Cask must not launch Settings" if check_source.include?("/usr/bin/open")

# Keep native directive dispatch and successor checks, but never cross the
# AppleScript boundary into the user's running app or real login items.
OSASCRIPT_CALLS = []
# Records native service-removal dispatch without unloading the user's real cleanup agent.
LAUNCHCTL_CALLS = []
FAILED_STATUS = SystemCommand.run("/usr/bin/false").status
# Intercepts desktop/service effects after Homebrew's real uninstall directive dispatch.
module IsolatedUninstallAutomation
  # Models service removal without consulting or changing the real user's launchd domain.
  def uninstall_launchctl(*services, command:, **_kwargs)
    raise "Unexpected service removal" unless services == ["dev.patsch.MatrixWallpaper.cleanup"]

    LAUNCHCTL_CALLS.concat(services)
    FileUtils.rm_f(ROOT/"job")
  end

  def system_command(executable, **options)
    return super unless File.basename(executable.to_s) == "osascript"

    raise "Unexpected automation artifact" unless cask.token == "matrix-screen-saver"

    OSASCRIPT_CALLS << options.fetch(:args)
    # Not running; login removal fails to exercise native best-effort handling.
    SystemCommand::Result.new([executable.to_s, *options.fetch(:args)], [], FAILED_STATUS, secrets: [])
  end
end
Cask::Artifact::AbstractUninstall.prepend(IsolatedUninstallAutomation)

# Observe real stage ordering and plant real quarantine on fixture bytes before
# preflight. No native filesystem/download/quarantine operation is mocked.
module StageObservation
  def stage
    super
    raise "Receipt missing after real stage" unless cask.installed?

    cask.artifacts.select { |a| a.is_a?(Cask::Artifact::ScreenSaver) || a.is_a?(Cask::Artifact::App) }.each do |artifact|
      raise "Source or target escaped isolation" unless [artifact.source, artifact.target].all? { |p| p.to_s.start_with?("#{ROOT}/") }

      executable = artifact.source.extname == ".app" ? "MatrixWallpaper" : "MatrixScreenSaver"
      (artifact.source/"Contents/MacOS"/executable).chmod(0755)
      [artifact.source, artifact.source/"Contents/MacOS"/executable].each do |path|
        SystemCommand.run!("/usr/bin/xattr", args: ["-w", "com.apple.quarantine", "0081;00000000;fixture;", path.to_s])
      end
    end
  end
end
Cask::Installer.prepend(StageObservation)

def check(value, message)
  raise message unless value
end

def capture
  old_out, old_err = $stdout, $stderr
  output = StringIO.new
  $stdout = $stderr = output
  yield
  output.string
ensure
  $stdout, $stderr = old_out, old_err
end

def definition(version, legacy: nil)
  source = case legacy
  when :saver then Pathname("Tests/Homebrew/fixtures/legacy-screen-saver.rb")
  when :wallpaper then Pathname("Tests/Homebrew/fixtures/legacy-wallpaper.rb")
  else ROOT/"handoff-#{version}/Casks/matrix-screen-saver.rb"
  end
  content = source.read
  content.gsub!('"HOME" => user_home', '"HOME" => user_home, "PATH" => "' + FIXTURE_BIN.to_s + ':/usr/bin:/bin:/usr/sbin:/sbin"')
  content.sub!("user_home = Dir.home", "user_home = #{FIXTURE_HOME.to_s.inspect}")
  content.sub!('version "0.2.0"', "version \"#{version}\"")
  content.sub!(/sha256 "[0-9a-f]+"/, "sha256 \"#{Digest::SHA256.file(ROOT/"#{version}.zip").hexdigest}\"")
  content.sub!(/^  url .+$/, "  url \"file://#{ROOT}/#{version}.zip\"")
  # Give the fixture a real isolated tap source for saved metadata and reloads.
  (TAP.path/"Casks/matrix-screen-saver.rb").write(content)
  loaded = nil
  output = capture { loaded = Cask::CaskLoader::FromContentLoader.new(content, tap: TAP).load(config: CONFIG) }
  check(!output.match?(/deprecated/i), "Definition load emitted deprecation warnings: #{output}")
  loaded
end

def verify_target(version, targets: TARGETS)
  targets.each do |target|
    info = SystemCommand.run!("/usr/libexec/PlistBuddy",
                              args: ["-c", "Print :CFBundleShortVersionString", (target/"Contents/Info.plist").to_s])
    check(info.stdout.strip == version, "Native target has wrong version")
    executable = target.extname == ".app" ? "MatrixWallpaper" : "MatrixScreenSaver"
    [target, target/"Contents/MacOS"/executable].each do |path|
      result = SystemCommand.run("/usr/bin/xattr", args: ["-p", "com.apple.quarantine", path.to_s], print_stderr: false)
      check(!result.success?, "Quarantine survived preflight")
    end
  end
  check(PREFS.read == "saved options\x00", "Preferences changed")
  if targets == TARGETS
    check((FIXTURE_HOME/"Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist").exist?, "Cleanup registration missing")
  end
end

# Verifies native uninstall dispatch and filesystem cleanup while retaining preference sentinels.
def uninstall(cask)
  OSASCRIPT_CALLS.clear
  LAUNCHCTL_CALLS.clear
  output = capture { Cask::Installer.new(cask).uninstall }
  check(!output.match?(/deprecated/i), "Uninstall emitted deprecation warnings")
  check(!output.include?(COFFEE), "Uninstall printed install success")
  check(TARGETS.none? { |target| target.exist? || target.symlink? }, "Native uninstall left target")
  check(OSASCRIPT_CALLS.any? { |args| args.last == "dev.patsch.MatrixWallpaper" }, "Native quit did not probe running app")
  login_calls = OSASCRIPT_CALLS.select { |args| args.join.include?("delete every login item") }
  check(login_calls.any? { |args| args.last.include?(APP_TARGET.to_s.inspect) }, "Native path login removal not attempted")
  check(login_calls.any? { |args| args.last.include?("Matrix Wallpaper".inspect) }, "Native named login removal not attempted")
  check(output.include?("failed"), "Failed login cleanup did not warn")
  check(PREFS.read == "saved options\x00", "Uninstall changed preferences")
  check(!(FIXTURE_HOME/"Library/LaunchAgents/dev.patsch.MatrixWallpaper.cleanup.plist").exist?, "Cleanup registration survived uninstall")
  check(LAUNCHCTL_CALLS == ["dev.patsch.MatrixWallpaper.cleanup"], "Native cleanup service removal not dispatched")
  check(!(ROOT/"job").exist?, "Cleanup service survived uninstall")
end

# Restore the native artifact from app resources while retaining Homebrew's real receipt and paths.
def restore_saver
  recovery = APP_TARGET/"Contents/Resources/ScreenSaver"
  recovery.mkpath
  FileUtils.cp("Scripts/product-lifecycle.sh", recovery/"product-lifecycle.sh")
  SystemCommand.run!("/usr/bin/xcrun", args: ["swiftc", "Tools/ScreenSaverInstaller.swift", "-o",
                                            (APP_TARGET/"Contents/MacOS/MatrixScreenSaverInstaller").to_s])
  SystemCommand.run!("/usr/bin/ditto", args: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                            TARGET.to_s, (recovery/"MatrixScreenSaver.zip").to_s])
  app_inode = APP_TARGET.stat.ino
  record = FIXTURE_HOME/"Library/Application Support/MatrixWallpaper/Installation/installation.plist"
  registration = record.binread
  SystemCommand.run!("/bin/bash", args: [(recovery/"product-lifecycle.sh").to_s, "activate", APP_TARGET.to_s],
                     env: { "HOME" => FIXTURE_HOME.to_s,
                            "PATH" => "#{FIXTURE_SERVICES}:#{FIXTURE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" })
  check((ROOT/"job").exist?, "App launch did not activate deferred cleanup")
  TARGET.rmtree
  SystemCommand.run!("/bin/bash", args: [(recovery/"product-lifecycle.sh").to_s, "install-saver", APP_TARGET.to_s],
                                 env: { "HOME" => FIXTURE_HOME.to_s,
                            "PATH" => "#{FIXTURE_SERVICES}:#{FIXTURE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" })
  check(TARGET.directory?, "Recovery did not restore the configured Homebrew target")
  check(APP_TARGET.stat.ino == app_inode, "Recovery replaced the wallpaper app")
  check(record.binread == registration, "Recovery changed Homebrew ownership or registration")
end

# AE1: modern steps run in Homebrew's real sandbox, including actual echo stdout.
fresh = definition("1.2.3")
check(!fresh.installed?, "Fresh fixture unexpectedly managed")
check(!fresh.depends_on.macos.allows?(MacOSVersion.from_symbol(:sonoma)), "Cask permits macOS before 15")
check(fresh.depends_on.macos.allows?(MacOSVersion.from_symbol(:sequoia)), "Cask rejects macOS 15")
intel = Cask::Installer.new(fresh)
intel.instance_variable_set(:@current_arch, { type: :intel, bits: 64 })
begin
  intel.check_arch_requirements
  raise "Cask unexpectedly permits Intel"
rescue Cask::CaskError => error
  check(error.message.include?("hardware architecture"), "Unexpected architecture rejection")
end
puts "PASS native dependency guards reject Intel and macOS before 15"
output = capture { Cask::Installer.new(fresh).install }
puts output
check(output.scan(COFFEE).length == 1, "Fresh coffee output count wrong")
check(output.include?("Open System Settings > Wallpaper > Screen Saver"), "Manual selection guidance missing")
check(output.include?("Open #{APP_TARGET} to start Matrix Wallpaper."), "Wallpaper launch guidance missing configured app path")
check(!output.match?(/deprecated/i), "Install emitted deprecation warnings")
verify_target("1.2.3")
check(!(ROOT/"job").exist?, "Sandboxed install unexpectedly activated cleanup")
check(OSASCRIPT_CALLS.empty?, "Install attempted startup or cleanup")
puts "PASS AE1 sandboxed native fresh install and actual coffee stdout"

restore_saver
verify_target("1.2.3")
uninstall(fresh)
OSASCRIPT_CALLS.clear
legacy = definition("1.2.2", legacy: :saver)
capture { Cask::Installer.new(legacy).install }
verify_target("1.2.2", targets: [TARGET])
check(!APP_TARGET.exist?, "Legacy fixture installed an app")
APP_TARGET.mkpath
(APP_TARGET/"manual-executable").write("manual sentinel")
conflicting = definition("1.2.3")
failed = false
output = capture do
  begin
    Cask::Upgrade.upgrade_cask(legacy, conflicting, binaries: true, force: false,
                             require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                             download_queue: Homebrew::DownloadQueue.default,
                             new_cask_installer: Cask::Installer.new(conflicting, upgrade: true))
  rescue Cask::CaskError
    failed = true
  end
end
check(failed, "Legacy upgrade unexpectedly replaced a manual app")
check((APP_TARGET/"manual-executable").read == "manual sentinel", "Legacy upgrade changed manual app")
verify_target("1.2.2", targets: [TARGET])
check(output.include?("Reverting upgrade"), "Failed legacy upgrade did not report rollback")
FileUtils.remove_entry(APP_TARGET)
puts "PASS native legacy upgrade conflict preserves manual app and restores saver"
fresh = definition("1.2.3")
output = capture do
  Cask::Upgrade.upgrade_cask(legacy, fresh, binaries: true, force: false,
                           require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                           download_queue: Homebrew::DownloadQueue.default,
                           new_cask_installer: Cask::Installer.new(fresh, upgrade: true))
end
verify_target("1.2.3")
check(output.scan(COFFEE).length == 1, "Legacy migration coffee output count wrong")
check(OSASCRIPT_CALLS.empty?, "Legacy migration attempted automation")
puts "PASS native legacy saver-only to dual-bundle migration"

# Recovery must leave the native artifact ready for Homebrew's next upgrade.
restore_saver
verify_target("1.2.3")

# AE4: successor evaluates while prior metadata exists, before native upgrade.
successor = definition("1.2.4")
OSASCRIPT_CALLS.clear
check(successor.installed?, "Successor did not observe prior metadata")
output = capture do
  Cask::Upgrade.upgrade_cask(fresh, successor, binaries: true, force: false,
                           require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                           download_queue: Homebrew::DownloadQueue.default,
                           new_cask_installer: Cask::Installer.new(successor, upgrade: true))
end
verify_target("1.2.4")
check(output.scan(COFFEE).length == 1, "Upgrade coffee output count wrong")
check(!output.match?(/deprecated/i), "Upgrade emitted deprecation warnings")
check(OSASCRIPT_CALLS.none? { |args| args.join.include?("delete every login item") }, "Upgrade removed login items")
puts "PASS AE4 real two-version native upgrade"

reinstall = definition("1.2.4")
OSASCRIPT_CALLS.clear
output = capture { Cask::Installer.new(reinstall, reinstall: true).install }
check(OSASCRIPT_CALLS.none? { |args| args.join.include?("delete every login item") }, "Reinstall removed login items")
check(output.scan(COFFEE).length == 1, "Reinstall coffee output count wrong")
verify_target("1.2.4")
uninstall(reinstall)
puts "PASS AE5 native uninstall and managed reinstall preference retention"

# The receipt owns the old filename; native upgrade must restore it on failure.
old_name = definition("1.2.1", legacy: :wallpaper)
capture { Cask::Installer.new(old_name).install }
verify_target("1.2.1", targets: [TARGET, LEGACY_APP_TARGET])
APP_TARGET.mkpath
(APP_TARGET/"manual-executable").write("manual sentinel")
renamed = definition("1.2.4")
failed = false
output = capture do
  begin
    Cask::Upgrade.upgrade_cask(old_name, renamed, binaries: true, force: false,
                             require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                             download_queue: Homebrew::DownloadQueue.default,
                             new_cask_installer: Cask::Installer.new(renamed, upgrade: true))
  rescue Cask::CaskError
    failed = true
  end
end
check(failed, "Rename upgrade unexpectedly replaced an unrelated app")
check((APP_TARGET/"manual-executable").read == "manual sentinel", "Rename upgrade changed unrelated app")
verify_target("1.2.1", targets: [TARGET, LEGACY_APP_TARGET])
check(output.include?("Reverting upgrade"), "Rename upgrade did not report rollback")
FileUtils.remove_entry(APP_TARGET)
renamed = definition("1.2.4")
OSASCRIPT_CALLS.clear
capture do
  Cask::Upgrade.upgrade_cask(old_name, renamed, binaries: true, force: false,
                           require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                           download_queue: Homebrew::DownloadQueue.default,
                           new_cask_installer: Cask::Installer.new(renamed, upgrade: true))
end
verify_target("1.2.4")
check(!LEGACY_APP_TARGET.exist?, "Rename upgrade left the old app filename")
check(OSASCRIPT_CALLS.none? { |args| args.join.include?("delete every login item") }, "Rename upgrade removed login items")
uninstall(renamed)
puts "PASS native old-name app upgrade, conflict rollback, and preference retention"

# Missing legacy artifacts and a partially completed upgrade must remain recoverable.
[:saver, :app, :interrupted_upgrade].each do |missing|
  legacy = definition("1.2.1", legacy: :wallpaper)
  capture { Cask::Installer.new(legacy).install }
  if missing == :app
    LEGACY_APP_TARGET.rmtree
  else
    TARGET.rmtree
  end
  successor = definition("1.2.4")
  if missing == :interrupted_upgrade
    begin
      capture do
        Cask::Upgrade.upgrade_cask(legacy, successor, binaries: true, force: false,
                                  require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                                  download_queue: Homebrew::DownloadQueue.default,
                                  new_cask_installer: Cask::Installer.new(successor, upgrade: true))
      end
      raise "Missing saver unexpectedly allowed a normal upgrade"
    rescue Cask::CaskError => error
      check(error.message.include?(TARGET.to_s) && error.message.include?("not there"),
            "Unexpected missing-saver upgrade failure: #{error}")
    end
    check(!LEGACY_APP_TARGET.exist?, "Failed upgrade did not reproduce removed legacy app")
    check((legacy.staged_path/"MatrixWallpaper.app").directory?, "Failed upgrade lost app backup")
  end
  recovery = definition("1.2.4")
  output = capture { Cask::Installer.new(recovery, reinstall: true, force: true).install }
  verify_target("1.2.4")
  check(!LEGACY_APP_TARGET.exist?, "Recovery left the old app filename")
  check(recovery.installed_version == "1.2.4", "Recovery left an outdated installed receipt")
  check(output.scan(COFFEE).length == 1, "Recovery did not report exactly one install success")
  uninstall(recovery)
  puts "PASS forced reinstall recovers #{missing} and preserves preferences"
end

# AE2/AE3: existing manual bundle survives native rejection, then explicit force replaces.
TARGETS.each do |target|
  target.mkpath
  (target/"manual-executable").write("manual sentinel")
  SystemCommand.run!("/usr/bin/xattr", args: ["-w", "com.apple.quarantine", "manual-quarantine", target.to_s])
  manual = definition("1.2.3")
  failed = false
  output = capture do
    begin
      Cask::Installer.new(manual).install
    rescue Cask::CaskError => error
      failed = true
      check(error.message.include?("already"), "Unexpected native conflict: #{error}")
    end
  end
  check(failed, "Native artifact did not reject manual conflict")
  check((target/"manual-executable").read == "manual sentinel", "Manual bundle changed")
  check((TARGETS - [target]).none?(&:exist?), "Native rollback left the other bundle installed")
  quarantine = SystemCommand.run!("/usr/bin/xattr", args: ["-p", "com.apple.quarantine", target.to_s])
  check(quarantine.stdout.strip == "manual-quarantine", "Preflight changed manual target quarantine")
  check(output.include?("brew install --cask --force patrickschaper/tap/matrix-screen-saver"), "Missing qualified migration guidance")
  check(output.include?(APP_TARGET.to_s), "Missing configured app destination guidance") if target == APP_TARGET
  check(!output.include?(COFFEE), "Failure printed success")
  check(PREFS.read == "saved options\x00", "Conflict changed preferences")
  forced = definition("1.2.3")
  output = capture { Cask::Installer.new(forced, force: true).install }
  verify_target("1.2.3")
  check(!(target/"manual-executable").exist?, "Force did not replace manual bundle")
  check(output.scan(COFFEE).length == 1, "Forced migration success output wrong")
  uninstall(forced)
end
puts "PASS AE2/AE3 native conflict rejection and explicit force replacement"

# The lifecycle refuses redirected destinations even when native force would replace them.
File.symlink(ROOT/"missing", TARGET)
broken = definition("1.2.3")
output = capture do
  begin
    Cask::Installer.new(broken).install
    raise "Native artifact accepted broken symlink without force"
  rescue StandardError => error
    check(error.message.include?("symlink"), "Unexpected broken-symlink rejection")
  end
end
check(TARGET.symlink?, "Broken symlink was changed")
check(!output.include?(COFFEE), "Broken-symlink conflict printed success")
check(!output.include?("brew install --cask --force"), "Existence guard unexpectedly matched broken symlink")
forced = definition("1.2.3")
begin
  capture { Cask::Installer.new(forced, force: true).install }
  raise "Force unexpectedly accepted a symlink"
rescue StandardError => error
  check(error.message.include?("symlink"), "Unexpected force rejection")
end
check(TARGET.symlink?, "Force changed the rejected symlink")
TARGET.unlink
puts "PASS redirected destinations remain untouched with or without force"
definition("1.2.3")
puts "PASS developer-mode definition load and uninstall without legacy warnings"
puts "PASS all native lifecycle checks; real apps, login items, installed bundles and Settings were never touched"
