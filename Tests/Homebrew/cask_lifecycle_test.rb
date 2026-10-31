require "tmpdir"
require_relative "support/fake_cask_dsl"
require_relative "support/test_harness"

class CaskLifecycleTest < TestHarness
  COFFEE = "There is no spoon. There is coffee: https://www.buymeacoffee.com/yesman82".freeze

  def setup
    @root = Dir.mktmpdir("matrix-cask-")
    @prefs = Pathname(@root)/"preferences-sentinel"
    @prefs.write("saved options\x00")
  end

  def teardown = FileUtils.remove_entry(@root)

  def definition(occupied: false, broken: false, artifact_index: 1)
    dsl = FakeCaskDSL.new(@root)
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

  def test_modern_definition_is_inert_until_install
    dsl = definition
    assert_empty dsl.commands
    dsl.install
    assert_success(dsl)
    assert_equal({arch: :arm64, macos: :sequoia}, dsl.dependencies)
    assert dsl.messages.any? { |m| m.include?("Gatekeeper") }
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

  def test_no_preference_cleanup_artifact
    dsl = definition
    assert_equal ["MatrixWallpaper.app", "MatrixScreenSaver.saver"], dsl.artifacts.map { |a| a.source.basename.to_s }
    assert_equal ["Matrix Wallpaper.app", "MatrixScreenSaver.saver"], dsl.artifacts.map { |a| a.target.basename.to_s }
    assert_equal({quit: "dev.patsch.MatrixWallpaper", login_item: "Matrix Wallpaper"}, dsl.uninstall_directives)
    source = File.read(File.expand_path("../../Homebrew/Casks/matrix-screen-saver.rb", __dir__))
    refute_match(/\b(zap|defaults|unregister|launchctl)\b/, source)
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
