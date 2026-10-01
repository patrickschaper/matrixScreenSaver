# Dependency-free assertions for Homebrew's bundled Ruby.
class TestHarness
  def assert(value, message = "assertion failed")
    raise message unless value
  end

  def refute(value) = assert(!value)
  def assert_equal(expected, actual) = assert(expected == actual, "expected #{expected.inspect}, got #{actual.inspect}")
  def assert_empty(value) = assert(value.empty?)
  def refute_includes(collection, value) = refute(collection.include?(value))
  def refute_match(pattern, value) = refute(pattern.match?(value))

  def assert_raises(type)
    begin
      yield
    rescue type => error
      return error
    end
    raise "expected #{type}"
  end

  def self.inherited(child)
    at_exit do
      failures = 0
      tests = child.instance_methods.grep(/^test_/).sort
      tests.each do |name|
        test = child.new
        begin
          test.setup
          test.public_send(name)
          puts "PASS #{name}"
        rescue StandardError => error
          failures += 1
          warn "FAIL #{name}: #{error.full_message}"
        ensure
          test.teardown
        end
      end
      puts "#{tests.length} tests, #{failures} failures"
      exit 1 if failures.positive?
    end
  end
end
