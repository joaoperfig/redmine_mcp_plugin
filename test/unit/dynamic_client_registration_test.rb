# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpPluginDcrPolicyTest < ActiveSupport::TestCase
  DCR = RedmineMcpPlugin::DynamicClientRegistration

  def teardown
    Setting.clear_cache
  end

  def with_settings_hash(hash)
    Setting.plugin_redmine_mcp_plugin = hash
    Setting.clear_cache
    yield
  end

  def all_on(overrides = {})
    RedmineMcpPlugin::Settings::DEFAULTS
      .merge('enabled' => '1', 'auth_oauth2' => '1', 'dcr_enabled' => '1')
      .merge(overrides)
  end

  def params(overrides = {})
    ActionController::Parameters.new(
      { token_endpoint_auth_method: 'none',
        redirect_uris: ['http://127.0.0.1:8080/callback'] }.merge(overrides)
    )
  end

  def test_gate_open_only_when_enabled_oauth2_and_dcr_all_on
    with_settings_hash(all_on)                              { assert DCR.gate_open? }
    with_settings_hash(all_on('enabled' => '0'))           { assert_not DCR.gate_open? }
    with_settings_hash(all_on('auth_oauth2' => '0'))       { assert_not DCR.gate_open? }
    with_settings_hash(all_on('dcr_enabled' => '0'))       { assert_not DCR.gate_open? }
  end

  def test_gate_closed_on_defaults
    with_settings_hash(RedmineMcpPlugin::Settings::DEFAULTS) { assert_not DCR.gate_open? }
  end

  def test_only_token_endpoint_auth_method_none_is_public
    assert DCR.public_client?(params('token_endpoint_auth_method' => 'none'))
    assert_not DCR.public_client?(params('token_endpoint_auth_method' => 'client_secret_basic'))
    assert_not DCR.public_client?(params('token_endpoint_auth_method' => 'client_secret_post'))
  end

  def test_missing_auth_method_is_not_public
    assert_not DCR.public_client?(ActionController::Parameters.new(redirect_uris: ['https://a.example/cb']))
  end

  def test_loopback_and_https_redirects_are_acceptable
    assert DCR.acceptable_redirect_uri?('http://127.0.0.1:8080/cb')
    assert DCR.acceptable_redirect_uri?('http://localhost:1234/cb')
    assert DCR.acceptable_redirect_uri?('http://[::1]:9000/cb')
    assert DCR.acceptable_redirect_uri?('https://app.example.com/cb')
  end

  def test_non_loopback_http_and_garbage_redirects_are_refused
    assert_not DCR.acceptable_redirect_uri?('http://evil.example.com/cb')
    assert_not DCR.acceptable_redirect_uri?('http://192.168.1.10/cb')
    assert_not DCR.acceptable_redirect_uri?('not a uri')
    assert_not DCR.acceptable_redirect_uri?('')
  end

  def test_every_redirect_uri_must_pass_and_at_least_one_is_required
    assert DCR.redirect_uris_acceptable?(params(redirect_uris: ['https://a.example/cb', 'http://localhost/cb']))
    assert_not DCR.redirect_uris_acceptable?(params(redirect_uris: ['https://a.example/cb', 'http://evil.example/cb']))
    assert_not DCR.redirect_uris_acceptable?(params(redirect_uris: []))
    assert_not DCR.redirect_uris_acceptable?(ActionController::Parameters.new({}))
  end

  def test_permitted_requires_gate_public_client_and_good_redirects
    with_settings_hash(all_on) do
      assert DCR.permitted?(params)
      assert_not DCR.permitted?(params('token_endpoint_auth_method' => 'client_secret_basic'))
      assert_not DCR.permitted?(params(redirect_uris: ['http://evil.example/cb']))
    end
  end

  def test_permitted_is_false_when_gate_closed_even_for_a_clean_request
    with_settings_hash(all_on('dcr_enabled' => '0')) { assert_not DCR.permitted?(params) }
  end
end
