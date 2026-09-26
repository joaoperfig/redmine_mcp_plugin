# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class McpControllerTest < Redmine::ControllerTest
  tests McpController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules, :time_entries

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

  # ActionController::TestCase#post takes no headers: keyword (that is the
  # integration-test API); request headers go on @request instead.
  def post_mcp(payload, headers = {})
    headers.each { |name, value| @request.headers[name] = value }
    post :handle, body: payload, as: :json
  end

  def json_body
    JSON.parse(response.body)
  end

  def api_key_headers(user)
    { 'X-Redmine-API-Key' => user.api_key }
  end

  # --- endpoint gating ---------------------------------------------------

  def test_endpoint_is_off_until_enabled
    enable_mcp('enabled' => '0')
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :forbidden
  end

  def test_unauthenticated_request_is_rejected
    post_mcp rpc('tools/list')
    assert_response :unauthorized
  end

  def test_invalid_api_key_is_rejected
    post_mcp rpc('tools/list'), 'X-Redmine-API-Key' => 'nonsense'
    assert_response :unauthorized
  end

  # A mode that is switched off must not authenticate, even with a valid
  # credential for that mode.
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

  # --- transport ----------------------------------------------------------

  def test_malformed_json_is_a_parse_error
    post_mcp '{not json', api_key_headers(User.find(2))
    assert_response :bad_request
    assert_equal RedmineMcpPlugin::JsonRpc::PARSE_ERROR, json_body['error']['code']
  end

  # Batching was removed from the protocol in 2025-06-18. Refusing it beats
  # processing element zero and silently dropping the rest.
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
    get :stream
    assert_response :method_not_allowed
  end

  def test_unknown_method_is_method_not_found
    post_mcp rpc('nonsense/method'), api_key_headers(User.find(2))
    assert_equal RedmineMcpPlugin::JsonRpc::METHOD_NOT_FOUND, json_body['error']['code']
  end

  # --- Origin / DNS rebinding --------------------------------------------

  def test_foreign_origin_is_rejected
    post_mcp rpc('tools/list'), api_key_headers(User.find(2)).merge('Origin' => 'https://evil.example')
    assert_response :forbidden
  end

  def test_configured_origin_is_allowed
    enable_mcp('allowed_origins' => 'https://friend.example')
    post_mcp rpc('tools/list'), api_key_headers(User.find(2)).merge('Origin' => 'https://friend.example')
    assert_response :success
  end

  # Every non-browser MCP client sends no Origin at all; they must not be
  # caught by the rebinding guard.
  def test_absent_origin_is_allowed
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_response :success
  end

  # --- protocol methods ---------------------------------------------------

  def test_server_discover_advertises_versions
    post_mcp rpc('server/discover'), api_key_headers(User.find(2))
    assert_response :success
    assert_equal RedmineMcpPlugin::SUPPORTED_PROTOCOL_VERSIONS, json_body['result']['protocolVersions']
  end

  def test_initialize_echoes_supported_version
    post_mcp rpc('initialize', { 'protocolVersion' => '2025-06-18' }), api_key_headers(User.find(2))
    assert_equal '2025-06-18', json_body['result']['protocolVersion']
  end

  def test_tools_list_is_cacheable_but_private
    post_mcp rpc('tools/list'), api_key_headers(User.find(2))
    assert_equal 'private', json_body['result']['cacheScope']
    assert json_body['result']['ttlMs'].to_i.positive?
  end

  # --- read-only mode -----------------------------------------------------

  def test_write_tools_are_hidden_in_read_only_mode
    post_mcp rpc('tools/list'), api_key_headers(User.find(1))
    names = json_body['result']['tools'].map { |t| t['name'] }
    assert_not_includes names, 'create_issue'
    assert_includes names, 'search_issues'
  end

  def test_write_tool_call_is_refused_in_read_only_mode
    post_mcp rpc('tools/call', { 'name' => 'create_issue',
                                 'arguments' => { 'project' => 'ecookbook', 'subject' => 'x' } }),
             api_key_headers(User.find(1))
    assert json_body['error'].present?
  end

  def test_write_tools_appear_when_read_only_is_off
    enable_mcp('read_only' => '0')
    post_mcp rpc('tools/list'), api_key_headers(User.find(1))
    assert_includes json_body['result']['tools'].map { |t| t['name'] }, 'create_issue'
  end

  # --- time entries -------------------------------------------------------

  def test_create_time_entry_logs_time_as_the_caller
    enable_mcp('read_only' => '0')
    user = User.find(2)
    assert_difference 'TimeEntry.count', 1 do
      post_mcp rpc('tools/call', { 'name' => 'create_time_entry',
                                   'arguments' => { 'issue_id' => 1, 'hours' => 1.5,
                                                    'spent_on' => '2026-09-24', 'comments' => 'Review' } }),
               api_key_headers(user)
    end

    payload = json_body['result']['structuredContent']
    assert_equal 1, payload['issue_id']
    assert_equal '2026-09-24', payload['spent_on']
    assert_equal user.id, TimeEntry.find(payload['id']).user_id
  end

  def test_create_time_entry_needs_an_issue_or_a_project
    enable_mcp('read_only' => '0')
    post_mcp rpc('tools/call', { 'name' => 'create_time_entry', 'arguments' => { 'hours' => 1 } }),
             api_key_headers(User.find(2))
    assert json_body['result']['isError']
  end

  # In project 1 jsmith is a Manager: edit_time_entries without
  # edit_own_time_entries. Core counts that as enough for an own entry.
  def test_update_time_entry_changes_own_entry
    enable_mcp('read_only' => '0')
    user = User.find(2)
    time_entry = TimeEntry.where(user_id: user.id).first
    post_mcp rpc('tools/call', { 'name' => 'update_time_entry',
                                 'arguments' => { 'id' => time_entry.id, 'hours' => 2.5, 'comments' => 'Edited' } }),
             api_key_headers(user)

    assert_equal 2.5, json_body['result']['structuredContent']['hours']
    assert_equal 'Edited', time_entry.reload.comments
  end

  # Somebody else's entry gets the same refusal as a missing one.
  def test_update_time_entry_refuses_another_users_entry
    enable_mcp('read_only' => '0')
    user = User.find(2)
    time_entry = TimeEntry.where.not(user_id: user.id).first
    post_mcp rpc('tools/call', { 'name' => 'update_time_entry', 'arguments' => { 'id' => time_entry.id, 'hours' => 1 } }),
             api_key_headers(user)

    assert json_body['result']['isError']
    assert_match(/No time entry of yours/, json_body['result']['content'].first['text'])
  end

  def test_delete_time_entry_removes_own_entry
    enable_mcp('read_only' => '0')
    user = User.find(2)
    time_entry = TimeEntry.where(user_id: user.id).first
    assert_difference 'TimeEntry.count', -1 do
      post_mcp rpc('tools/call', { 'name' => 'delete_time_entry', 'arguments' => { 'id' => time_entry.id } }),
               api_key_headers(user)
    end
    assert json_body['result']['structuredContent']['deleted']
  end

  def test_list_time_entries_only_returns_visible_rows
    user = User.find(2)
    post_mcp rpc('tools/call', { 'name' => 'list_time_entries' }), api_key_headers(user)
    assert_equal TimeEntry.visible(user).count, json_body['result']['structuredContent']['total_count']
  end

  # --- visibility ---------------------------------------------------------

  def test_whoami_reports_the_authenticated_user
    post_mcp rpc('tools/call', { 'name' => 'whoami' }), api_key_headers(User.find(2))
    payload = json_body['result']['structuredContent']
    assert_equal 2, payload['id']
    assert_equal 'api_key', payload['authentication_mode']
    assert_nil payload['oauth_scopes']
  end

  # An invisible issue and a nonexistent one must be indistinguishable, or the
  # error message confirms the existence of records the caller cannot see.
  def test_invisible_issue_is_reported_as_not_found
    issue = Issue.find(4)
    issue.update_columns(is_private: true)
    post_mcp rpc('tools/call', { 'name' => 'get_issue', 'arguments' => { 'id' => issue.id } }),
             api_key_headers(User.find(7))
    assert json_body['result']['isError']
    assert_match(/No visible issue/, json_body['result']['content'].first['text'])
  end

  def test_search_issues_only_returns_visible_rows
    user = User.find(7)
    post_mcp rpc('tools/call', { 'name' => 'search_issues', 'arguments' => { 'status' => 'all' } }),
             api_key_headers(user)
    returned = json_body['result']['structuredContent']['issues'].map { |i| i['id'] }
    assert_equal returned.sort, Issue.visible(user).where(id: returned).pluck(:id).sort
    assert Issue.count > returned.size, 'fixture set should be larger than what one user can see'
  end

  # list_users must not enumerate the directory: core's own users list is
  # admin-only and each role carries a users_visibility setting.
  def test_list_users_respects_users_visibility
    user = User.find(7)
    post_mcp rpc('tools/call', { 'name' => 'list_users' }), api_key_headers(user)
    total = json_body['result']['structuredContent']['total_count']
    assert_equal Principal.visible(user).where(type: 'User').active.count, total
  end
end
