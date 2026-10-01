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

  def definition(occupied: false, broken: false)
    dsl = FakeCaskDSL.new(@root)
    dsl.load_definition
    artifact = dsl.artifacts.first
    FileUtils.mkdir_p(artifact.source)
    (artifact.source/"executable").write("new")
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
    assert_equal "new", (dsl.artifacts.first.target/"executable").read
    quarantine = dsl.commands.find { |cmd, _| cmd == "/usr/bin/xattr" }
    assert_equal ["-dr", "com.apple.quarantine", dsl.artifacts.first.source.to_s], quarantine[1]
    assert_equal ["{{staged_path}}/MatrixScreenSaver.saver"], quarantine[2][:writable_paths]
    assert dsl.messages.any? { |m| m.include?("Open System Settings") }
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
    assert_equal "manual", (dsl.artifacts.first.target/"executable").read
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
    assert dsl.artifacts.first.target.symlink?
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
    FileUtils.rm_rf(dsl.artifacts.first.source)
    dsl.fail_quarantine = false
    assert_raises(RuntimeError) { dsl.install }
    assert_equal 2, dsl.commands.count { |cmd, _| cmd == "/usr/bin/xattr" }
    refute dsl.artifacts.first.target.exist?
    refute_includes dsl.messages, COFFEE
  end

  def test_no_preference_cleanup_artifact
    dsl = definition
    assert_equal 1, dsl.artifacts.length
    source = File.read(File.expand_path("../../Homebrew/Casks/matrix-screen-saver.rb", __dir__))
    refute_match(/\b(zap|defaults|uninstall)\b/, source)
  end
end
