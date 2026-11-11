require "pathname"
require "fileutils"

# Models only modern run/guard/steps; real sandbox and artifacts have integration coverage.
class FakeCaskDSL
  Artifact = Struct.new(:source, :target)
  attr_accessor :fail_quarantine
  attr_reader :artifacts, :commands, :dependencies, :messages, :uninstall_directives

  def initialize(root)
    @root = Pathname(root)
    @artifacts, @commands, @dependencies, @messages = [], [], {}, []
    @preflight, @postflight = [], []
  end

  def load_definition
    instance_eval(File.read(File.expand_path("../../../Homebrew/Casks/matrix-screen-saver.rb", __dir__)))
  end

  def cask(_token = nil, &block)
    block ? instance_eval(&block) : self
  end
  def config = self
  def screen_saverdir = @root/"custom savers"
  def version(value = nil)
    @version = value if value
    @version
  end

  %i[sha256 url name desc homepage].each { |key| define_method(key) { |*_args| } }
  def depends_on(**values) = @dependencies.merge!(values)
  def screen_saver(name)
    @artifacts << Artifact.new(@root/"stage"/name, @root/"custom savers"/name)
  end

  def app(name, target: name)
    @artifacts << Artifact.new(@root/"stage"/name, @root/"custom apps"/target)
  end

  def uninstall(**directives) = @uninstall_directives = directives

  # Records block or serialized steps without executing commands during definition loading.
  def preflight_steps(steps = nil, &block)
    @steps = @preflight
    if block
      instance_eval(&block)
    else
      record_steps(steps)
    end
  end

  # Records block or serialized steps without executing commands during definition loading.
  def postflight_steps(steps = nil, &block)
    @steps = @postflight
    if block
      instance_eval(&block)
    else
      record_steps(steps)
    end
  end

  # Records block or serialized steps without executing commands during definition loading.
  def uninstall_preflight_steps(steps = nil, &block)
    @steps = []
    if block
      instance_eval(&block)
    else
      record_steps(steps)
    end
  end

  def if_path_exists(path, base:, &block)
    @guard = expand("{{#{base}}}/#{path}")
    instance_eval(&block)
  ensure
    @guard = nil
  end

  # Models the serialized run/guard form used for paths captured from cask configuration.
  def record_steps(steps)
    steps.each do |step|
      raise "Unsupported step" unless step.fetch(:type) == :run

      guard = step.fetch(:guards, []).first
      guard = expand("{{#{guard.fetch(:base)}}}/#{guard.fetch(:path)}") if guard
      @steps << [step.fetch(:command), step.reject { |key, _| %i[type command guards].include?(key) }, guard]
    end
  end

  def run(command, **options) = @steps << [command, options, @guard]

  def expand(value)
    value.gsub("{{staged_path}}", (@root/"stage").to_s)
         .gsub("{{screen_saverdir}}", (@root/"custom savers").to_s)
         .gsub("{{appdir}}", (@root/"custom apps").to_s)
  end

  def execute(steps)
    steps.each do |command, options, guard|
      next if guard && !Pathname(guard).exist? # Homebrew 7.0.7 does not include broken symlinks.

      args = options.fetch(:args).map { |arg| expand(arg) }
      @commands << [command, args, options]
      @messages.concat(args) if command == "/bin/echo" && options[:print_stdout]
      if command == "/usr/bin/xattr"
        raise "quarantine failed" if @fail_quarantine || !Pathname(args.last).directory?
      end
    end
  end

  def install(force: false)
    execute(@preflight)
    # Only models conflict rejection, not Homebrew's filesystem rollback.
    @artifacts.each do |artifact|
      raise "native conflict" if !force && (artifact.target.exist? || artifact.target.symlink?)
    end
    @artifacts.each do |artifact|
      FileUtils.rm_rf(artifact.target) if force
      FileUtils.mkdir_p(artifact.target.dirname)
      FileUtils.mv(artifact.source, artifact.target)
    end
    execute(@postflight)
  end
end
