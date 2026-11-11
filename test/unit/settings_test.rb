# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpSettingsTest < ActiveSupport::TestCase
  S = RedmineMcp::Settings

  def teardown
    Setting.clear_cache
  end

  def with_settings_hash(hash)
    Setting.plugin_redmine_mcp = hash
    Setting.clear_cache
    yield
  end

  def test_text_falls_back_to_the_default_when_blank_or_absent
    with_settings_hash({}) { assert_equal 'built-in', S.text('prompt_x', 'built-in') }
    with_settings_hash('prompt_x' => " \r\n ") { assert_equal 'built-in', S.text('prompt_x', 'built-in') }
  end

  def test_text_returns_an_edit_with_lf_line_breaks
    with_settings_hash('prompt_x' => "line one\r\nline two") do
      assert_equal "line one\nline two", S.text('prompt_x', 'built-in')
    end
  end

  def test_server_instructions_default_and_override
    with_settings_hash({}) { assert_equal RedmineMcp::McpServer::INSTRUCTIONS, S.server_instructions }
    with_settings_hash('server_instructions' => 'Custom') { assert_equal 'Custom', S.server_instructions }
  end

  def test_symbol_keyed_settings_are_readable
    with_settings_hash(enabled: 'true', read_only: 'false') do
      assert S.enabled?
      assert_not S.read_only?
    end
  end

  def test_string_keyed_settings_are_readable
    with_settings_hash('enabled' => '1', 'read_only' => '0') do
      assert S.enabled?
      assert_not S.read_only?
    end
  end

  def test_bool_accepts_both_encodings
    with_settings_hash('enabled' => 'true')  { assert S.enabled? }
    with_settings_hash('enabled' => '1')     { assert S.enabled? }
    with_settings_hash('enabled' => 'false') { assert_not S.enabled? }
    with_settings_hash('enabled' => '0')     { assert_not S.enabled? }
    with_settings_hash({})                   { assert_not S.enabled? }
  end

  def test_dcr_enabled_defaults_off_and_reads_both_key_styles
    with_settings_hash({})                      { assert_not S.dcr_enabled? }
    with_settings_hash(S::DEFAULTS)             { assert_not S.dcr_enabled? }
    with_settings_hash(dcr_enabled: 'true')     { assert S.dcr_enabled? }
    with_settings_hash('dcr_enabled' => '1')    { assert S.dcr_enabled? }
    with_settings_hash('dcr_enabled' => '0')    { assert_not S.dcr_enabled? }
  end

  def test_max_results_is_capped_and_defaulted
    with_settings_hash('max_results' => '5')     { assert_equal 5, S.max_results }
    with_settings_hash('max_results' => '99999') { assert_equal S::ABSOLUTE_MAX_RESULTS, S.max_results }
    with_settings_hash('max_results' => '0')     { assert_equal 100, S.max_results }
    with_settings_hash('max_results' => 'abc')   { assert_equal 100, S.max_results }
  end

  def test_allowed_origins_splits_on_whitespace_and_commas
    with_settings_hash('allowed_origins' => "https://a.example\nhttps://b.example, https://c.example") do
      assert_equal %w[https://a.example https://b.example https://c.example], S.allowed_origins
    end
    with_settings_hash('allowed_origins' => '') { assert_equal [], S.allowed_origins }
  end

  def test_any_auth_mode_detects_all_modes_off
    with_settings_hash('auth_oauth2' => '0', 'auth_api_key' => '0', 'auth_basic' => '0', 'auth_session' => '0') do
      assert_not S.any_auth_mode?
    end
    with_settings_hash('auth_oauth2' => '0', 'auth_api_key' => '1', 'auth_basic' => '0', 'auth_session' => '0') do
      assert S.any_auth_mode?
    end
  end
end
