require "pathname"
require "fileutils"

# Models only the DSL boundary; native movement is separately integration-tested.
module Cask
  module Caskroom
    class << self
      attr_accessor :managed
      def cask_installed?(_token) = managed
    end
  end
  module Artifact
    class ScreenSaver
      attr_reader :source, :target

      def initialize(source, target)
        @source, @target = source, target
      end
    end
  end
end

class FakeCaskDSL
  attr_accessor :managed, :fail_quarantine, :fail_open
  attr_reader :artifacts, :commands, :dependencies, :messages

  def initialize(root, managed: false)
    @root, @managed = Pathname(root), managed
    @artifacts, @commands, @dependencies, @messages = [], [], {}, []
  end

  def load_definition
    Cask::Caskroom.managed = @managed
    instance_eval(File.read(File.expand_path("../../../Homebrew/Casks/matrix-screen-saver.rb", __dir__)))
  end

  def cask(_token = nil, &block)
    return self unless block

    @definition = block
    instance_eval(&block)
  end

  def version(value = nil)
    @version = value if value
    @version
  end

  %i[sha256 url name desc homepage].each { |key| define_method(key) { |*_args| } }
  def depends_on(**values)
    @dependencies.merge!(values)
  end

  def full_name = "fixture/tap/matrix-screen-saver"
  def screen_saver(name)
    @artifacts << Cask::Artifact::ScreenSaver.new(@root/"stage"/name, @root/"custom savers"/name)
  end

  def preflight(&block) = @preflight = block
  def postflight(&block) = @postflight = block
  def ohai(message) = @messages << message
  def opoo(message) = @messages << message

  def system_command(executable, **options)
    @commands << [executable, options.fetch(:args)]
    raise "quarantine failed" if executable == "/usr/bin/xattr" && @fail_quarantine
    raise "settings unavailable" if executable == "/usr/bin/open" && @fail_open
  end

  def install(force: false)
    @managed = true # Homebrew saves metadata BEFORE invoking preflight.
    Cask::Caskroom.managed = true
    @artifacts.clear
    instance_eval(&@definition) # Final config assignment refreshes the cask block.
    instance_eval(&@preflight)
    artifact = @artifacts.first
    if artifact.target.exist? || artifact.target.symlink?
      raise "native conflict" unless force
      FileUtils.rm_rf(artifact.target)
    end
    FileUtils.mkdir_p(artifact.target.dirname)
    FileUtils.mv(artifact.source, artifact.target)
    instance_eval(&@postflight)
  end
end
