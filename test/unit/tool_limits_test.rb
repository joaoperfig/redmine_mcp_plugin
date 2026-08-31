# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# limit_for and offset_for clamp as well as cap. SchemaValidator rejects values
# below a declared minimum, but only for a tool that declares one, so the
# clamping is what protects a list tool whose schema omits it.
class RedmineMcpPluginToolLimitsTest < ActiveSupport::TestCase
  class Probe < RedmineMcpPlugin::Tool
    tool 'probe', title: 'Probe', description: 'test', schema: { 'type' => 'object' }
    def limit(arguments)  = limit_for(arguments)
    def offset(arguments) = offset_for(arguments)
  end

  def setup
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS.merge('max_results' => '100')
    Setting.clear_cache
    @probe = Probe.new(nil)
  end

  def teardown
    Setting.clear_cache
  end

  def test_limit_defaults_to_max_results
    assert_equal 100, @probe.limit({})
  end

  def test_limit_is_capped_at_max_results
    assert_equal 100, @probe.limit('limit' => 5000)
  end

  def test_limit_is_clamped_to_one
    assert_equal 1, @probe.limit('limit' => 0)
    assert_equal 1, @probe.limit('limit' => -5)
  end

  def test_offset_defaults_to_zero
    assert_equal 0, @probe.offset({})
  end

  def test_offset_is_clamped_to_zero
    assert_equal 0, @probe.offset('offset' => -1)
  end

  def test_offset_passes_through
    assert_equal 250, @probe.offset('offset' => 250)
  end
end
