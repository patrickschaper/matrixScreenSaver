# Run through `brew ruby`; never through a brew install/uninstall command.
require "cask/cask_loader"
require "cask/installer"
require "cask/upgrade"
require "digest"
require "stringio"

ENV.delete("HOMEBREW_DEVELOPER")
ROOT = Pathname(ARGV.fetch(0)).realpath
raise "Unsafe test root" unless ROOT.basename.to_s.start_with?("matrix-homebrew-integration.")
raise "Homebrew 7.0.7 is required for this compatibility test" unless HOMEBREW_VERSION.start_with?("7.0.7")
raise "Cache escaped isolation" unless HOMEBREW_CACHE.realpath.to_s.start_with?("#{ROOT}/")

# Redirect Homebrew's in-process Caskroom and tap objects, not the host installation.
Cask::Caskroom.instance_variable_set(:@path, ROOT/"Caskroom")
TAP = Tap.fetch("matrix-fixture/homebrew-test")
TAP.instance_variable_set(:@path, ROOT/"tap")
(TAP.path/"Casks").mkpath
CONFIG = Cask::Config.new(explicit: Cask::Config::DEFAULT_DIRS.keys.to_h { |key| [key, ROOT/key.to_s] })
TARGET = CONFIG.screen_saverdir/"MatrixScreenSaver.saver"
PREFS = ROOT/"preferences-sentinel"
PREFS.write("saved options\x00")
COFFEE = "There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82".freeze
SETTINGS = "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension".freeze

# Legacy blocks ignore the installer's command parameter. Intercept the default
# class and ONLY this exact absolute executable/argument pair; everything else runs.
module SettingsIntercept
  attr_accessor :settings_calls, :fail_settings

  def run!(executable, **options)
    if executable.to_s == "/usr/bin/open"
      raise "Unexpected open invocation" unless options[:args] == [SETTINGS]

      self.settings_calls += 1
      raise "Simulated headless settings failure" if fail_settings

      return nil
    end
    super
  end
end
SystemCommand.singleton_class.prepend(SettingsIntercept)
SystemCommand.settings_calls = 0

# Observe real stage ordering and plant real quarantine on fixture bytes before
# preflight. No native filesystem/download/artifact/quarantine operation is mocked.
module StageObservation
  def stage
    super
    raise "Receipt missing after real stage" unless cask.installed?

    saver = cask.artifacts.grep(Cask::Artifact::ScreenSaver).fetch(0)
    raise "Source or target escaped isolation" unless [saver.source, saver.target].all? { |p| p.to_s.start_with?("#{ROOT}/") }

    SystemCommand.run!("/usr/bin/xattr", args: ["-w", "com.apple.quarantine", "0081;00000000;fixture;", saver.source.to_s])
    SystemCommand.run!("/usr/bin/xattr", args: ["-w", "com.apple.quarantine", "0081;00000000;fixture;",
                                             (saver.source/"Contents/MacOS/MatrixScreenSaver").to_s])
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

def definition(version)
  content = Pathname("Homebrew/Casks/matrix-screen-saver.rb").read
  content.sub!('version "0.2.0"', "version \"#{version}\"")
  content.sub!(/sha256 "[0-9a-f]+"/, "sha256 \"#{Digest::SHA256.file(ROOT/"#{version}.zip").hexdigest}\"")
  content.sub!(/^  url .+$/, "  url \"file://#{ROOT}/#{version}.zip\"")
  # Give the fixture a real isolated tap source for saved metadata and reloads.
  (TAP.path/"Casks/matrix-screen-saver.rb").write(content)
  Cask::CaskLoader::FromContentLoader.new(content, tap: TAP).load(config: CONFIG)
end

def verify_target(version)
  info = SystemCommand.run!("/usr/libexec/PlistBuddy",
                            args: ["-c", "Print :CFBundleShortVersionString", (TARGET/"Contents/Info.plist").to_s])
  check(info.stdout.strip == version, "Native target has wrong version")
  [TARGET, TARGET/"Contents/MacOS/MatrixScreenSaver"].each do |path|
    result = SystemCommand.run("/usr/bin/xattr", args: ["-p", "com.apple.quarantine", path.to_s], print_stderr: false)
    check(!result.success?, "Quarantine survived preflight")
  end
  check(PREFS.read == "saved options\x00", "Preferences changed")
end

def uninstall(cask)
  Cask::Installer.new(cask).uninstall
  check(!TARGET.exist? && !TARGET.symlink?, "Native uninstall left target")
  check(PREFS.read == "saved options\x00", "Uninstall changed preferences")
end

# AE1: stage saves metadata, but the definition snapshot still opens once.
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
check(SystemCommand.settings_calls == 1, "Fresh setup not called exactly once (#{SystemCommand.settings_calls})")
check(output.scan(COFFEE).length == 1, "Fresh coffee output count wrong")
verify_target("1.2.3")
puts "PASS AE1 native fresh install and real stage snapshot"

# AE4: successor evaluates while prior metadata exists, before native upgrade.
successor = definition("1.2.4")
check(successor.installed?, "Successor did not observe prior metadata")
output = capture do
  Cask::Upgrade.upgrade_cask(fresh, successor, binaries: true, force: false,
                           require_sha: true, quit: false, skip_cask_deps: false, verbose: false,
                           download_queue: Homebrew::DownloadQueue.default,
                           new_cask_installer: Cask::Installer.new(successor, upgrade: true))
end
verify_target("1.2.4")
check(SystemCommand.settings_calls == 1, "Upgrade opened settings")
check(output.scan(COFFEE).length == 1 && !output.include?("brew install --cask --force"), "Upgrade guidance wrong")
puts "PASS AE4 real two-version native upgrade"

reinstall = definition("1.2.4")
capture { Cask::Installer.new(reinstall, reinstall: true).install }
check(SystemCommand.settings_calls == 1, "Reinstall opened settings")
verify_target("1.2.4")
uninstall(reinstall)
puts "PASS AE5 native uninstall and managed reinstall preference retention"

# AE2/AE3: existing manual bundle survives native rejection, then explicit force replaces.
TARGET.mkpath
(TARGET/"manual-executable").write("manual sentinel")
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
check((TARGET/"manual-executable").read == "manual sentinel", "Manual bundle changed")
check(output.include?("brew install --cask --force #{manual.full_name}"), "Missing qualified migration guidance")
check(!output.include?(COFFEE) && SystemCommand.settings_calls == 1, "Failure printed success or opened settings")
check(PREFS.read == "saved options\x00", "Conflict changed preferences")
forced = definition("1.2.3")
output = capture { Cask::Installer.new(forced, force: true).install }
verify_target("1.2.3")
check(!(TARGET/"manual-executable").exist?, "Force did not replace manual bundle")
check(output.scan(COFFEE).length == 1 && SystemCommand.settings_calls == 2, "Forced migration setup wrong")
uninstall(forced)
puts "PASS AE2/AE3 native conflict rejection and explicit force replacement"

SystemCommand.fail_settings = true
headless = definition("1.2.3")
output = capture { Cask::Installer.new(headless).install }
verify_target("1.2.3")
check(output.include?("Could not open settings") && output.scan(COFFEE).length == 1, "Headless fallback missing")
uninstall(headless)
puts "PASS failed settings launch retains successful native installation"

ENV["HOMEBREW_DEVELOPER"] = "1"
begin
  definition("1.2.3")
  raise "Developer mode unexpectedly accepted deprecated hooks"
rescue MethodDeprecatedError => error
  check(error.message.include?("preflight"), "Unexpected developer-mode failure")
  puts "PASS expected developer-mode preflight deprecation rejection"
ensure
  ENV.delete("HOMEBREW_DEVELOPER")
end
puts "PASS all native lifecycle checks; installed saver and real Settings were never touched"
