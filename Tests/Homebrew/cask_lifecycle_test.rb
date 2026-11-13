require "tmpdir"
require_relative "support/fake_cask_dsl"
require_relative "support/test_harness"

class CaskLifecycleTest < TestHarness
  # Expected post-install donation message, including the shared guidance prefix.
  COFFEE = "➡️ There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82".freeze

  def setup
    @root = Dir.mktmpdir("matrix-cask-")
    @prefs = Pathname(@root)/"preferences-sentinel"
    @prefs.write("saved options\x00")
  end

  def teardown = FileUtils.remove_entry(@root)

  def definition(occupied: false, broken: false, artifact_index: 1, installed: false, command: "install")
    previous_command = Homebrew.running_command_with_args.split[1]
    Homebrew.running_command = command
    dsl = FakeCaskDSL.new(@root)
    dsl.installed = installed
    dsl.load_definition
    dsl.artifacts.each do |item|
      FileUtils.mkdir_p(item.source)
      (item.source/"executable").write("new")
    end
    artifact = dsl.artifacts.fetch(artifact_index)
    FileUtils.mkdir_p(artifact.target.dirname)
    if broken
      File.symlink("missing", artifact.target)
    elsif occupied
      FileUtils.mkdir_p(artifact.target)
      (artifact.target/"executable").write("manual")
    end
    dsl
  ensure
    Homebrew.running_command = previous_command
  end

  def assert_success(dsl)
    assert_equal 1, dsl.messages.count(COFFEE)
    refute dsl.commands.any? { |cmd, _| cmd == "/usr/bin/open" }
    assert_equal "saved options\x00", @prefs.read
    dsl.artifacts.each do |artifact|
      assert_equal "new", (artifact.target/"executable").read
      quarantine = dsl.commands.find { |cmd, args| cmd == "/usr/bin/xattr" && args.last == artifact.source.to_s }
      assert quarantine, "missing quarantine removal for #{artifact.source}"
      assert_equal ["-dr", "com.apple.quarantine", artifact.source.to_s], quarantine[1]
      assert_equal ["{{staged_path}}/#{artifact.source.basename}"], quarantine[2][:writable_paths]
    end
    assert dsl.messages.any? { |m| m.include?("Open System Settings") }
    assert dsl.messages.any? { |m| m.include?("Open #{dsl.artifacts.first.target} to start Matrix Wallpaper.") }
  end

  # Checks the prefix on install notices and both artifact-conflict messages.
  def test_all_homebrew_messages_have_arrow_prefix
    [0, 1].each do |artifact_index|
      dsl = definition(occupied: true, artifact_index: artifact_index)
      dsl.install(force: true)
      dsl.messages.each { |message| assert message.start_with?("➡️ "), message }
    end
  end

  def test_modern_definition_is_inert_until_install
    dsl = definition
    assert_empty dsl.commands
    dsl.install
    assert_success(dsl)
    assert_equal({arch: :arm64, macos: :sequoia}, dsl.dependencies)
    assert dsl.messages.any? { |m| m.include?("Gatekeeper") }
  end

  # Initial receipt state must survive Homebrew's post-staging reload.
  def test_fresh_install_selects_after_registration_with_scoped_store_access
    dsl = definition
    dsl.install
    selections = dsl.commands.select { |cmd, _| cmd.end_with?("/MatrixScreenSaverSelector") }
    assert_equal 1, selections.length
    command, args, options = selections.first
    assert_equal "#{dsl.artifacts.first.target}/Contents/MacOS/MatrixScreenSaverSelector", command
    assert_equal [dsl.artifacts.last.target.to_s], args
    assert_equal({ "HOME" => Dir.home }, options[:env])
    assert_equal true, options[:allow_failure]
    assert options[:writable_paths].include?("#{Dir.home}/Library/Application Support/com.apple.wallpaper/Store")
    registration = dsl.commands.index { |_, arguments| arguments.include?("register") }
    assert registration < dsl.commands.index(selections.first)
    assert_success(dsl)
  end

  def test_upgrade_preserves_selection_from_prior_receipt
    dsl = definition(installed: true, command: "upgrade")
    # Staging changes receipt state; the definition must retain the earlier snapshot.
    dsl.installed = false
    dsl.install
    refute dsl.commands.any? { |cmd, _| cmd.end_with?("/MatrixScreenSaverSelector") }
    assert_success(dsl)
  end

  def test_explicit_reinstall_selects_despite_an_existing_receipt
    dsl = definition(installed: true, command: "reinstall")
    dsl.install
    selections = dsl.commands.select { |cmd, _| cmd.end_with?("/MatrixScreenSaverSelector") }
    assert_equal 1, selections.length
    assert_equal [dsl.artifacts.last.target.to_s], selections.first[1]
    assert_success(dsl)
  end

  def test_selection_failure_keeps_installation_and_manual_recovery_guidance
    dsl = definition
    dsl.fail_selection = true
    dsl.install
    assert dsl.commands.any? { |cmd, _| cmd.end_with?("/MatrixScreenSaverSelector") }
    assert_success(dsl)
  end

  def test_unforced_conflict_is_delegated_and_never_prints_success
    dsl = definition(occupied: true)
    assert_raises(RuntimeError) { dsl.install }
    assert_equal "manual", (dsl.artifacts.fetch(1).target/"executable").read
    assert dsl.messages.any? { |m| m.include?("brew install --cask --force patrickschaper/tap/matrix-screen-saver") }
    guidance = dsl.commands.find { |_, args, _| args.any? { |arg| arg.include?("--force") } }
    assert_equal [{ path: "MatrixScreenSaver.saver", base: :screen_saverdir }], guidance[2][:writable_paths]
    refute_includes dsl.messages, COFFEE
    refute dsl.commands.any? { |cmd, _| cmd == "/usr/bin/open" }
    assert_equal "saved options\x00", @prefs.read
  end

  def test_forced_migration
    dsl = definition(occupied: true)
    dsl.install(force: true)
    assert_success(dsl)
  end

  def test_broken_symlink_is_left_to_native_conflict_handling
    dsl = definition(broken: true)
    assert_raises(RuntimeError) { dsl.install }
    assert dsl.artifacts.fetch(1).target.symlink?
    refute dsl.messages.any? { |m| m.include?("--force") }
    refute_includes dsl.messages, COFFEE
    dsl.install(force: true)
    assert_success(dsl)
  end

  def test_quarantine_failure_and_missing_source_abort
    dsl = definition
    dsl.fail_quarantine = true
    assert_raises(RuntimeError) { dsl.install }
    refute dsl.artifacts.first.target.exist?
    refute_includes dsl.messages, COFFEE
    FileUtils.rm_rf(dsl.artifacts.fetch(1).source)
    dsl.fail_quarantine = false
    assert_raises(RuntimeError) { dsl.install }
    assert_equal 2, dsl.commands.count { |cmd, _| cmd == "/usr/bin/xattr" }
    refute dsl.artifacts.first.target.exist?
    refute_includes dsl.messages, COFFEE
  end

  # User-only service removal must never ask Homebrew to probe root services.
  def test_no_preference_cleanup_artifact
    dsl = definition
    assert_equal ["MatrixWallpaper.app", "MatrixScreenSaver.saver"], dsl.artifacts.map { |a| a.source.basename.to_s }
    assert_equal ["Matrix Wallpaper.app", "MatrixScreenSaver.saver"], dsl.artifacts.map { |a| a.target.basename.to_s }
    assert_equal({script: { executable: "/bin/launchctl",
                           args: ["bootout", "gui/#{Process.uid}/dev.patsch.MatrixWallpaper.cleanup"],
                           sudo: false, must_succeed: false },
                  quit: "dev.patsch.MatrixWallpaper", login_item: "Matrix Wallpaper"}, dsl.uninstall_directives)
    source = File.read(File.expand_path("../../Homebrew/Casks/matrix-screen-saver.rb", __dir__))
    refute_match(/\b(zap|defaults)\b/, source)
    assert source.include?("uninstall_preflight_steps")
    assert source.include?('"unregister"')
    refute_match(/\b(?:preflight|postflight|uninstall_preflight|uninstall_postflight)\s+do/, source)
    refute_match(/\/usr\/bin\/open|osascript|--register/, source)
  end

  def test_app_conflict_uses_custom_appdir_and_never_prints_success
    dsl = definition(occupied: true, artifact_index: 0)
    assert_raises(RuntimeError) { dsl.install }
    assert_equal "manual", (dsl.artifacts.first.target/"executable").read
    guidance = dsl.commands.find { |_, args| args.any? { |arg| arg.include?("Existing app at #{@root}/custom apps/Matrix Wallpaper.app") } }
    assert guidance, "missing custom appdir conflict guidance"
    assert_equal [{path: "Matrix Wallpaper.app", base: :appdir}], guidance[2][:writable_paths]
    refute_includes dsl.messages, COFFEE
    assert_equal "saved options\x00", @prefs.read
    dsl.install(force: true)
    assert_success(dsl)
  end

  def test_missing_app_aborts_before_install_success
    dsl = definition
    FileUtils.remove_entry(dsl.artifacts.first.source)
    assert_raises(RuntimeError) { dsl.install }
    refute dsl.artifacts.any? { |a| a.target.exist? }
    refute_includes dsl.messages, COFFEE
    assert_equal "saved options\x00", @prefs.read
  end
end
