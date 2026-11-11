# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require 'securerandom'
require 'digest'
require 'base64'

class OauthAuthorizationFlowTest < Redmine::IntegrationTest
  REDIRECT_URI = 'http://127.0.0.1:8080/callback'

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

  def register_public_client
    post '/oauth/registration',
         params: { token_endpoint_auth_method: 'none',
                   redirect_uris: [REDIRECT_URI],
                   client_name: 'Flow Test Client',
                   scope: 'view_issues' },
         as: :json
    assert_response :created
    JSON.parse(response.body).fetch('client_id')
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  def authorization_code(client_id, challenge)
    post '/oauth/authorize',
         params: { client_id: client_id,
                   redirect_uri: REDIRECT_URI,
                   response_type: 'code',
                   scope: 'view_issues',
                   code_challenge: challenge,
                   code_challenge_method: 'S256' }
    assert_response :redirect
    Rack::Utils.parse_query(URI.parse(response.location).query)['code']
  end

  def test_register_authorize_and_token_exchange_succeeds
    client_id = register_public_client
    log_user('jsmith', 'jsmith')

    verifier, challenge = pkce_pair
    code = authorization_code(client_id, challenge)
    assert code.present?, 'authorize should redirect with an authorization code'

    post '/oauth/token',
         params: { grant_type: 'authorization_code',
                   code: code,
                   redirect_uri: REDIRECT_URI,
                   client_id: client_id,
                   code_verifier: verifier }

    assert_response :success
    assert JSON.parse(response.body)['access_token'].present?,
           'token exchange should return an access_token'
  end
end
