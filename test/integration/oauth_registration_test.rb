# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class OauthRegistrationTest < Redmine::IntegrationTest
  def setup
    super
    Setting.rest_api_enabled = '1'
    enable_dcr
  end

  def teardown
    Setting.clear_cache
  end

  def enable_dcr(overrides = {})
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS
        .merge('enabled' => '1', 'auth_oauth2' => '1', 'dcr_enabled' => '1')
        .merge(overrides)
    Setting.clear_cache
  end

  def register(body)
    post '/oauth/registration', params: body, as: :json
  end

  def public_client_body(redirect = 'http://127.0.0.1:8080/callback')
    { token_endpoint_auth_method: 'none',
      redirect_uris: [redirect],
      client_name: 'Test MCP Client' }
  end

  def test_public_registration_succeeds_and_creates_one_public_application
    assert_difference 'Doorkeeper::Application.count', 1 do
      register public_client_body
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert body['client_id'].present?, 'response should carry a client_id'

    app = Doorkeeper::Application.find_by(uid: body['client_id'])
    assert_not_nil app, 'the advertised client_id should resolve to an application'
    assert_not app.confidential, 'a registered client must be public'
  end

  def test_https_redirect_registration_succeeds
    assert_difference 'Doorkeeper::Application.count', 1 do
      register public_client_body('https://app.example.com/callback')
    end
    assert_response :created
  end

  def test_registration_accepts_a_permission_name_scope
    assert_difference 'Doorkeeper::Application.count', 1 do
      register public_client_body.merge(scope: 'view_issues')
    end
    assert_response :created
    assert_includes JSON.parse(response.body)['scope'].split, 'view_issues'
  end

  def test_registration_refused_when_dcr_disabled
    enable_dcr('dcr_enabled' => '0')
    assert_no_difference 'Doorkeeper::Application.count' do
      register public_client_body
    end
    assert_not_equal 201, response.status
  end

  def test_registration_refused_when_endpoint_disabled
    enable_dcr('enabled' => '0')
    assert_no_difference 'Doorkeeper::Application.count' do
      register public_client_body
    end
    assert_not_equal 201, response.status
  end

  def test_registration_refused_when_oauth2_mode_off
    enable_dcr('auth_oauth2' => '0')
    assert_no_difference 'Doorkeeper::Application.count' do
      register public_client_body
    end
    assert_not_equal 201, response.status
  end

  def test_confidential_registration_is_refused
    assert_no_difference 'Doorkeeper::Application.count' do
      register public_client_body.merge(token_endpoint_auth_method: 'client_secret_basic')
    end
    assert_not_equal 201, response.status
  end

  def test_non_loopback_http_redirect_is_refused
    assert_no_difference 'Doorkeeper::Application.count' do
      register public_client_body('http://evil.example.com/callback')
    end
    assert_not_equal 201, response.status
  end
end
