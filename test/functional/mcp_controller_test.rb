# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class McpControllerTest < Redmine::ControllerTest
  tests McpController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules

  # The bootstrap challenge advertises OAUTH_BOOTSTRAP_SCOPES: the three core read
  # scopes plus the two read satellites (watchers, time entries) that ticket 07
  # folds into bootstrap. No write scope and no view_private_notes.
  OAUTH_CHALLENGE =
    'Bearer realm="Redmine", resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
    'scope="view_issues view_project view_wiki_pages view_issue_watchers view_time_entries"'

  def setup
    Setting.rest_api_enabled = '1'
    enable_mcp('enabled' => '1')
    User.current = nil
  end

  def teardown
    Setting.clear_cache
    User.current = nil
  end

  def enable_mcp(overrides = {})
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS.merge('enabled' => '1').merge(overrides)
    Setting.clear_cache
  end

  def rpc(method, params = nil, id: 1)
    body = { jsonrpc: '2.0', id: id, method: method }
    body[:params] = params if params
    body.to_json
  end

  def post_mcp(payload, headers = {})
    @request.headers.merge!(
      'Authorization' => nil,
      'X-Redmine-API-Key' => nil,
      'Origin' => nil
    )
    @request.headers.merge!(headers)
    post :handle, body: payload
  end

  def json_body
    JSON.parse(response.body)
  end

  def api_key_headers(user)
    { 'X-Redmine-API-Key' => user.api_key }
  end

  def oauth_headers(user, scopes:)
    application = Doorkeeper::Application.create!(
      name: 'MCP controller test', redirect_uri: 'https://client.example/callback', scopes: scopes
    )
    token = Doorkeeper::AccessToken.create!(
      application_id: application.id, resource_owner_id: user.id, scopes: scopes, expires_in: 7200
    )
    { 'Authorization' => "Bearer #{token.plaintext_token}" }
  end

  def test_endpoint_is_off_until_enabled
    enable_mcp('enabled' => '0')
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :forbidden
  end

  def test_unauthenticated_request_is_rejected
    post_mcp rpc('tools/list')

    assert_response :unauthorized
    assert_equal OAUTH_CHALLENGE, response.headers['WWW-Authenticate']
  end

  def test_invalid_oauth_token_challenge_includes_minimal_bootstrap_scopes
    post_mcp rpc('tools/list'), 'Authorization' => 'Bearer invalid-token'

    assert_response :unauthorized
    assert_equal OAUTH_CHALLENGE, response.headers['WWW-Authenticate']
  end

  def test_invalid_api_key_is_rejected
    post_mcp rpc('tools/list'), 'X-Redmine-API-Key' => 'nonsense'
    assert_response :unauthorized
  end

  def test_disabled_api_key_mode_rejects_a_valid_key
    enable_mcp('auth_api_key' => '0', 'auth_oauth2' => '0', 'auth_basic' => '0', 'auth_session' => '0')
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :service_unavailable
  end

  def test_api_key_mode_requires_rest_api_enabled
    Setting.rest_api_enabled = '0'
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :unauthorized
  end

  def test_malformed_json_is_a_parse_error
    post_mcp '{not json', api_key_headers(User.find(2))
    assert_response :bad_request
    assert_equal RedmineMcpPlugin::JsonRpc::PARSE_ERROR, json_body['error']['code']
  end

  def test_authentication_precedes_json_rpc_parsing
    post_mcp '{not json'

    assert_response :unauthorized
    assert_equal 'Authentication failed', json_body['error']
  end

  def test_batches_are_refused
    post_mcp [{ jsonrpc: '2.0', id: 1, method: 'tools/list' }].to_json, api_key_headers(User.find(2))
    assert_response :bad_request
    assert_equal RedmineMcpPlugin::JsonRpc::INVALID_REQUEST, json_body['error']['code']
  end

  def test_notification_gets_202_with_no_body
    post_mcp({ jsonrpc: '2.0', method: 'notifications/initialized' }.to_json, api_key_headers(User.find(2)))
    assert_response :accepted
    assert response.body.blank?
  end

  def test_unsupported_protocol_version_is_a_400
    post_mcp rpc('tools/list'), api_key_headers(User.find(2)).merge('MCP-Protocol-Version' => '1999-01-01')
    assert_response :bad_request
    assert_equal RedmineMcpPlugin::JsonRpc::UNSUPPORTED_PROTOCOL_VERSION, json_body['error']['code']
  end

  def test_get_returns_405_because_there_is_no_stream
    @request.headers.merge!(api_key_headers(User.find(2)))
    get :stream
    assert_response :method_not_allowed
  end

  def test_unknown_method_is_method_not_found
    post_mcp rpc('nonsense/method'), api_key_headers(User.find(2))
    assert_equal JsonRpcHandler::ErrorCode::METHOD_NOT_FOUND, json_body['error']['code']
  end

  def test_foreign_origin_is_rejected
    post_mcp rpc('tools/list'), api_key_headers(User.find(2)).merge('Origin' => 'https://evil.example')
    assert_response :forbidden
  end

  def test_foreign_origin_is_rejected_before_authentication
    post_mcp rpc('tools/list'), 'Origin' => 'https://evil.example'

    assert_response :forbidden
    assert_equal 'Origin not allowed', json_body['error']
  end

  def test_configured_origin_is_allowed
    enable_mcp('allowed_origins' => 'https://friend.example')
    post_mcp rpc('tools/list'), api_key_headers(User.find(2)).merge('Origin' => 'https://friend.example')
    assert_response :success
  end

  def test_absent_origin_is_allowed
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :success
  end

  def test_server_discover_advertises_versions
    post_mcp rpc('server/discover'), api_key_headers(User.find(2))
    assert_response :success
    assert_equal ['2026-07-28'], json_body['result']['supportedVersions']
  end

  def test_initialize_echoes_supported_handshake_version
    post_mcp rpc('initialize', initialize_params('2025-06-18')), api_key_headers(User.find(2))
    assert_equal '2025-06-18', json_body['result']['protocolVersion']
  end

  def test_initialize_counteroffers_a_handshake_version_for_a_modern_version
    post_mcp rpc('initialize', initialize_params('2026-07-28')), api_key_headers(User.find(2))

    assert_equal '2025-11-25', json_body['result']['protocolVersion']
  end

  def test_server_protocol_state_is_isolated_per_request
    headers = api_key_headers(User.find(2))
    payload = rpc('initialize', initialize_params('2025-11-25'))

    2.times do
      post_mcp payload, headers
      assert_equal '2025-11-25', json_body.dig('result', 'protocolVersion')
    end
  end

  def test_legacy_tools_list_has_no_modern_result_or_cache_metadata
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    result = json_body['result']

    assert_not result.key?('resultType')
    assert_not result.key?('_meta')
    assert_not result.key?('cacheScope')
    assert_not result.key?('ttlMs')
  end

  def test_write_tools_are_hidden_in_read_only_mode
    post_mcp rpc('tools/list'), api_key_headers(User.find(1))
    names = json_body['result']['tools'].pluck('name')
    assert_not_includes names, 'create_issue'
    assert_includes names, 'search_issues'
  end

  def test_write_tool_call_is_refused_in_read_only_mode
    post_mcp rpc('tools/call', { 'name' => 'create_issue',
                                 'arguments' => { 'project' => 'ecookbook', 'subject' => 'x' } }),
             oauth_headers(User.find(2), scopes: 'view_issues')
    assert_response :forbidden
    assert_nil response.headers['WWW-Authenticate']
  end

  def test_unknown_tool_remains_an_sdk_not_found_error
    post_mcp rpc('tools/call', { 'name' => 'not_registered', 'arguments' => {} }),
             api_key_headers(User.find(1))

    assert_equal(-32_602, json_body.dig('error', 'code'))
    assert_equal 'Invalid params', json_body.dig('error', 'message')
    assert_equal 'Tool not found: not_registered', json_body.dig('error', 'data')
  end

  def test_write_tools_appear_when_read_only_is_off
    enable_mcp('read_only' => '0')
    post_mcp rpc('tools/list'), api_key_headers(User.find(1))
    assert_includes json_body['result']['tools'].pluck('name'), 'create_issue'
  end

  def test_whoami_reports_the_authenticated_user
    post_mcp rpc('tools/call', { 'name' => 'whoami' }), api_key_headers(User.find(2))
    payload = json_body['result']['structuredContent']
    assert_equal 2, payload['id']
    assert_equal 'api_key', payload['authentication_mode']
    assert_nil payload['oauth_scopes']
  end

  def test_oauth_scope_does_not_hide_tools_permitted_by_the_users_role
    user = User.find(2)

    post_mcp rpc('tools/list'), api_key_headers(user)
    api_key_tools = json_body['result']['tools'].pluck('name')
    assert_includes api_key_tools, 'list_projects'
    assert_includes api_key_tools, 'search_issues'

    oauth = oauth_headers(user, scopes: 'view_issues')
    post_mcp rpc('tools/list'), oauth
    oauth_tools = json_body['result']['tools'].pluck('name')
    assert_includes oauth_tools, 'whoami'
    assert_includes oauth_tools, 'list_users'
    assert_includes oauth_tools, 'list_enumerations'
    assert_includes oauth_tools, 'list_projects'
    assert_includes oauth_tools, 'search_issues'

    post_mcp rpc('tools/call', { 'name' => 'search_issues' }), oauth
    assert_not json_body.dig('result', 'isError')
  end

  def test_read_scope_challenge_never_includes_write_scopes
    oauth = oauth_headers(User.find(2), scopes: 'view_issues')

    post_mcp rpc('tools/call', { 'name' => 'list_projects' }), oauth

    assert_response :forbidden
    # view_project correlates one hop to its same-tier reads; the challenge stays
    # entirely within the read tier and never introduces a write scope.
    assert_equal(
      'Bearer error="insufficient_scope", scope="view_project view_issues view_wiki_pages", ' \
      'resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
      'error_description="The access token lacks the scope required for this operation"',
      response.headers['WWW-Authenticate']
    )
  end

  def test_issue_creation_challenge_includes_all_same_tier_correlated_scopes
    enable_mcp('read_only' => '0')
    oauth = oauth_headers(User.find(2), scopes: 'view_issues')

    post_mcp rpc('tools/call', { 'name' => 'create_issue',
                                 'arguments' => { 'project' => 'ecookbook', 'subject' => 'x' } }), oauth

    assert_response :forbidden
    assert_equal(
      'Bearer error="insufficient_scope", scope="add_issues add_issue_notes", ' \
      'resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
      'error_description="The access token lacks the scope required for this operation"',
      response.headers['WWW-Authenticate']
    )
  end

  def test_private_issue_note_challenge_includes_every_required_scope
    enable_mcp('read_only' => '0')
    oauth = oauth_headers(User.find(2), scopes: 'add_issue_notes')

    post_mcp rpc('tools/call', { 'name' => 'add_issue_note',
                                 'arguments' => { 'id' => 1, 'notes' => 'Private', 'private' => true } }), oauth

    assert_response :forbidden
    assert_equal(
      'Bearer error="insufficient_scope", scope="add_issue_notes set_notes_private", ' \
      'resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
      'error_description="The access token lacks the scope required for this operation"',
      response.headers['WWW-Authenticate']
    )
  end

  def test_oauth_administrator_without_a_grantable_role_is_challenged_for_admin
    enable_mcp('read_only' => '0')
    administrator = User.find(4)
    administrator.update_columns(admin: true)
    assert_not administrator.roles.any? { |role| role.allowed_to?(:set_notes_private) }
    assert_not administrator.builtin_role.allowed_to?(:set_notes_private)

    post_mcp rpc('tools/call', { 'name' => 'add_issue_note',
                                 'arguments' => { 'id' => 1, 'notes' => 'Private', 'private' => true } }),
             oauth_headers(administrator, scopes: 'view_issues')

    assert_response :forbidden
    assert_equal(
      'Bearer error="insufficient_scope", scope="admin", ' \
      'resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
      'error_description="The access token lacks the scope required for this operation"',
      response.headers['WWW-Authenticate']
    )

    post_mcp rpc('tools/call', { 'name' => 'add_issue_note',
                                 'arguments' => { 'id' => 1, 'notes' => 'Authorized', 'private' => true } }),
             oauth_headers(administrator, scopes: 'admin')
    assert_response :success
    assert_not json_body.dig('result', 'isError')
  end

  def test_admin_only_read_authorization_does_not_challenge_for_write_tier_admin
    Role.non_member.remove_permission!(:view_wiki_pages)
    administrator = User.find(4)
    administrator.update_columns(admin: true)
    assert_not administrator.roles.any? { |role| role.allowed_to?(:view_wiki_pages) }

    post_mcp rpc('tools/call', { 'name' => 'list_wiki_pages' }),
             oauth_headers(administrator, scopes: 'view_issues')

    assert_response :forbidden
    assert_nil response.headers['WWW-Authenticate']
  end

  def test_oauth_scope_does_not_expose_tools_denied_by_the_users_role
    Role.non_member.remove_permission!(:view_wiki_pages)
    oauth = oauth_headers(User.find(7), scopes: 'view_wiki_pages')

    post_mcp rpc('tools/list'), oauth
    assert_not_includes json_body['result']['tools'].pluck('name'), 'list_wiki_pages'

    post_mcp rpc('tools/call', { 'name' => 'list_wiki_pages' }), oauth
    assert_response :forbidden
    assert_nil response.headers['WWW-Authenticate']
  end

  def test_permissionless_tools_need_no_oauth_scope
    post_mcp rpc('tools/list'), oauth_headers(User.find(2), scopes: '')

    names = json_body['result']['tools'].pluck('name')
    assert_includes names, 'whoami'
    assert_includes names, 'list_users'
    assert_includes names, 'list_enumerations'
  end

  def test_sdk_schema_failure_is_an_error_tool_result
    post_mcp rpc('tools/call', { 'name' => 'get_project', 'arguments' => {} }),
             api_key_headers(User.find(2))

    assert json_body.dig('result', 'isError')
    assert_equal 'Missing required arguments: project', json_body.dig('result', 'content', 0, 'text')
  end

  def test_unexpected_tool_exception_does_not_leak_internal_details
    secret = 'private-database-detail-/var/redmine'
    Issue.stubs(:visible).raises(StandardError, secret)

    post_mcp rpc('tools/call', { 'name' => 'get_issue', 'arguments' => { 'id' => 1 } }),
             api_key_headers(User.find(2))

    assert_equal(-32_603, json_body.dig('error', 'code'))
    assert_equal 'Internal error', json_body.dig('error', 'message')
    assert_equal 'Internal error calling tool get_issue', json_body.dig('error', 'data')
    assert_not_includes response.body, secret
  end

  def test_control_characters_are_not_rejected_at_the_mcp_boundary
    post_mcp rpc('tools/call', { 'name' => 'search_issues', 'arguments' => { 'query' => "a\u0007b" } }),
             api_key_headers(User.find(2))

    assert_not json_body.dig('result', 'isError')
  end

  # Keep invisible and nonexistent issues indistinguishable to prevent record
  # existence from leaking through error text.
  def test_invisible_issue_is_reported_as_not_found
    issue = Issue.find(4)
    issue.update_columns(is_private: true)
    post_mcp rpc('tools/call', { 'name' => 'get_issue', 'arguments' => { 'id' => issue.id } }),
             api_key_headers(User.find(7))
    assert_response :success
    assert json_body['result']['isError']
    assert_match(/No visible issue/, json_body['result']['content'].first['text'])
  end

  def test_search_issues_only_returns_visible_rows
    user = User.find(7)
    post_mcp rpc('tools/call', { 'name' => 'search_issues', 'arguments' => { 'status' => 'all' } }),
             api_key_headers(user)
    returned = json_body['result']['structuredContent']['issues'].pluck('id')
    assert_equal returned.sort, Issue.visible(user).where(id: returned).pluck(:id).sort
    assert Issue.count > returned.size, 'fixture set should be larger than what one user can see'
  end

  def test_list_users_respects_users_visibility
    user = User.find(7)
    post_mcp rpc('tools/call', { 'name' => 'list_users' }), api_key_headers(user)
    total = json_body['result']['structuredContent']['total_count']
    assert_equal Principal.visible(user).where(type: 'User').active.count, total
  end

  private

  def initialize_params(version)
    {
      'protocolVersion' => version,
      'capabilities' => {},
      'clientInfo' => { 'name' => 'controller-test', 'version' => '1.0.0' }
    }
  end
end
