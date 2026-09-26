# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class McpControllerTest < Redmine::ControllerTest
  tests McpController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :issue_categories, :versions, :issue_relations, :workflows, :projects_trackers

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
    api_key_headers(User.find(2)).each { |name, value| @request.headers[name] = value }
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

  # --- issues -------------------------------------------------------------

  def test_update_issue_changes_fields
    enable_mcp('read_only' => '0')
    issue = Issue.find(1)
    assignee = issue.project.assignable_users.first
    post_mcp rpc('tools/call', { 'name' => 'update_issue',
                                 'arguments' => {
                                   'id' => issue.id,
                                   'subject' => 'Updated issue title',
                                   'status' => 'Closed',
                                   'done_ratio' => 100,
                                   'priority' => 'Urgent',
                                   'assigned_to' => assignee.login
                                 } }),
             api_key_headers(User.find(1))

    assert_response :success
    assert_equal 'Updated issue title', json_body['result']['structuredContent']['subject']
    assert_equal 'Closed', json_body['result']['structuredContent']['status']
    assert_equal 100, json_body['result']['structuredContent']['done_ratio']
    assert_equal assignee.login, User.find(json_body['result']['structuredContent']['assigned_to_id']).login
  end

  def test_create_issue_sets_parent_category_and_version
    enable_mcp('read_only' => '0')
    parent = Issue.find(1)
    category = parent.project.issue_categories.first
    version = parent.assignable_versions.first
    post_mcp rpc('tools/call', { 'name' => 'create_issue',
                                 'arguments' => {
                                   'project' => parent.project.identifier,
                                   'subject' => 'Child issue',
                                   'parent_issue_id' => parent.id,
                                   'category' => category.name,
                                   'fixed_version' => version.name
                                 } }),
             api_key_headers(User.find(1))

    assert_response :success
    result = json_body['result']['structuredContent']
    assert_equal parent.id, result['parent_id']
    assert_equal category.name, result['category']
    assert_equal version.name, result['fixed_version']
  end

  def test_create_issue_rejects_unknown_category
    enable_mcp('read_only' => '0')
    post_mcp rpc('tools/call', { 'name' => 'create_issue',
                                 'arguments' => { 'project' => 'ecookbook', 'subject' => 'x',
                                                  'category' => 'No such category' } }),
             api_key_headers(User.find(1))

    assert json_body['result']['isError']
    assert_equal 0, Issue.where(subject: 'x').count
  end

  def test_update_issue_clears_parent_with_none
    enable_mcp('read_only' => '0')
    child = Issue.generate!(project_id: 1, parent_issue_id: 1)
    post_mcp rpc('tools/call', { 'name' => 'update_issue',
                                 'arguments' => { 'id' => child.id, 'parent_issue_id' => 'none' } }),
             api_key_headers(User.find(1))

    assert_response :success
    assert_nil child.reload.parent_id
  end

  def test_add_issue_relation_links_issues_and_get_issue_reports_it
    enable_mcp('read_only' => '0')
    post_mcp rpc('tools/call', { 'name' => 'add_issue_relation',
                                 'arguments' => { 'issue_id' => 1, 'issue_to_id' => 2, 'relation_type' => 'blocks' } }),
             api_key_headers(User.find(1))

    assert_response :success
    assert IssueRelation.exists?(issue_from_id: 1, issue_to_id: 2, relation_type: 'blocks')

    post_mcp rpc('tools/call', { 'name' => 'get_issue', 'arguments' => { 'id' => 2, 'include_journals' => false } }),
             api_key_headers(User.find(1))
    relations = json_body['result']['structuredContent']['relations']
    assert_includes relations.map { |r| [r['issue_id'], r['relation_type']] }, [1, 'blocked']
  end

  # The uniqueness validation runs before core swaps blocked into blocks, so the
  # same link asked for from the other side used to reach the unique index and
  # come back as an internal error.
  def test_add_issue_relation_refuses_an_existing_link_asked_in_reverse
    enable_mcp('read_only' => '0')
    IssueRelation.create!(issue_from: Issue.find(1), issue_to: Issue.find(3), relation_type: 'blocks')
    post_mcp rpc('tools/call', { 'name' => 'add_issue_relation',
                                 'arguments' => { 'issue_id' => 3, 'issue_to_id' => 1, 'relation_type' => 'blocked' } }),
             api_key_headers(User.find(1))

    assert json_body['result']['isError']
    assert_match(/already related/, json_body['result']['content'].first['text'])
  end

  # safe_attributes= replaces a disallowed status silently; the tool must not
  # report that as success.
  def test_update_issue_refuses_a_status_the_workflow_does_not_allow
    enable_mcp('read_only' => '0')
    # Core fixtures let the Manager role reach every status; take Closed away.
    WorkflowTransition.where(role_id: 1, new_status_id: IssueStatus.find_by(name: 'Closed').id).delete_all
    issue = Issue.find(1)
    post_mcp rpc('tools/call', { 'name' => 'update_issue', 'arguments' => { 'id' => issue.id, 'status' => 'Closed' } }),
             api_key_headers(User.find(2))

    assert json_body['result']['isError']
    assert_not_equal 'Closed', issue.reload.status.name
  end

  def test_parent_needs_manage_subtasks
    enable_mcp('read_only' => '0')
    Role.find(1).remove_permission!(:manage_subtasks)
    post_mcp rpc('tools/call', { 'name' => 'update_issue', 'arguments' => { 'id' => 2, 'parent_issue_id' => 1 } }),
             api_key_headers(User.find(2))

    assert json_body['result']['isError']
    assert_nil Issue.find(2).parent_id
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
