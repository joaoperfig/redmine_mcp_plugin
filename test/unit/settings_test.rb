# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpPluginSettingsTest < ActiveSupport::TestCase
  S = RedmineMcpPlugin::Settings

  def teardown
    Setting.clear_cache
  end

  def with_settings_hash(hash)
    Setting.plugin_redmine_mcp_plugin = hash
    Setting.clear_cache
    yield
  end

  # The regression this whole module exists to prevent: before an administrator
  # saves the form, Redmine hands back init.rb's defaults hash verbatim. If that
  # hash is keyed by symbols, every string-keyed read returns nil and the plugin
  # silently behaves as though everything is switched off.
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

  # Checkboxes post '1'/'0'; DEFAULTS uses 'true'/'false'. Both must work.
  def test_bool_accepts_both_encodings
    with_settings_hash('enabled' => 'true')  { assert S.enabled? }
    with_settings_hash('enabled' => '1')     { assert S.enabled? }
    with_settings_hash('enabled' => 'false') { assert_not S.enabled? }
    with_settings_hash('enabled' => '0')     { assert_not S.enabled? }
    with_settings_hash({})                   { assert_not S.enabled? }
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
