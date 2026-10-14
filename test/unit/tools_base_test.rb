# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Exercises the SDK-backed tool base (Tools::Base < MCP::Tool): the two
# authorization locks, the argument/response plumbing of the class entry point,
# the derived annotations, and a real converted read tool running end to end
# through a mounted MCP::Server. These never touch the controller.
class RedmineMcpPluginToolsBaseTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :journals

  # A user test double: the locks only ask User#allowed_to?, so the probe tests
  # stay off the fixture set and assert the gate in isolation.
  class FakeUser
    def initialize(allowed:, allowed_permissions: nil)
      @allowed = allowed
      @allowed_permissions = allowed_permissions
    end

    attr_writer :oauth_scope

    def allowed_to?(permission, *, **)
      return @allowed if @allowed_permissions.nil?

      @allowed_permissions.include?(permission)
    end
  end

  class ReadProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'read_probe'
    title 'Read probe'
    description 'test'
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def perform(_arguments) = { ok: true }
  end

  class WriteProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'write_probe'
    title 'Write probe'
    description 'test'
    write true
    destructive true
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def perform(_arguments) = { created: true }
  end

  class PermProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'perm_probe'
    title 'Perm probe'
    description 'test'
    permission :view_issues
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def perform(_arguments) = { ok: true }
  end

  class ConditionalPermProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'conditional_perm_probe'
    title 'Conditional permission probe'
    description 'test'
    permission :view_issues
    input_schema({ 'type' => 'object', 'additionalProperties' => true })

    def self.required_permissions(arguments = {})
      arguments['elevated'] ? super + %i[edit_issues] : super
    end

    def perform(_arguments) = { ok: true }
  end

  class ErrorProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'error_probe'
    title 'Error probe'
    description 'test'
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def perform(_arguments) = raise(RedmineMcpPlugin::ToolError, 'nothing matched')
  end

  class PermissionErrorProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'permission_error_probe'
    title 'Permission error probe'
    description 'test'
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def perform(_arguments) = raise(RedmineMcpPlugin::PermissionError, 'not permitted')
  end

  # Exposes the protected pagination helpers so they can be asserted on the new
  # base directly, now that they no longer live on the legacy Tool.
  class HelperProbe < RedmineMcpPlugin::Tools::Base
    tool_name 'helper_probe'
    title 'Helper probe'
    description 'test'
    input_schema({ 'type' => 'object', 'additionalProperties' => false })

    def limit(arguments)  = limit_for(arguments)
    def offset(arguments) = offset_for(arguments)
    def page(**)          = paged(**)

    def perform(_arguments) = {}
  end

  def setup
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '1')
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  # --- Discovery lock: available_to? ---------------------------------------

  def test_permissionless_read_tool_is_available_to_anyone
    assert ReadProbe.available_to?(FakeUser.new(allowed: false), oauth_scopes: nil)
  end

  def test_permissioned_tool_follows_allowed_to
    assert PermProbe.available_to?(FakeUser.new(allowed: true), oauth_scopes: nil)
    assert_not PermProbe.available_to?(FakeUser.new(allowed: false), oauth_scopes: nil)
  end

  def test_write_tool_is_hidden_in_read_only_mode
    assert_not WriteProbe.available_to?(FakeUser.new(allowed: true), oauth_scopes: nil)
  end

  def test_write_tool_appears_when_read_only_is_off
    with_read_only_off do
      assert WriteProbe.available_to?(FakeUser.new(allowed: true), oauth_scopes: nil)
    end
  end

  # --- Execution lock: run re-checks before the body ------------------------

  def test_write_tool_execution_is_refused_in_read_only_mode
    result = WriteProbe.call(server_context: { user: FakeUser.new(allowed: true) }).to_h

    assert result[:isError]
    assert_equal RedmineMcpPlugin::Tools::Base::UNAVAILABLE, result[:content].first[:text]
  end

  def test_permission_denied_execution_is_refused
    result = PermProbe.call(server_context: { user: FakeUser.new(allowed: false) }).to_h

    assert result[:isError]
    assert_equal RedmineMcpPlugin::Tools::Base::UNAVAILABLE, result[:content].first[:text]
  end

  def test_argument_dependent_permission_is_rechecked_by_the_execution_backstop
    user = FakeUser.new(allowed: true, allowed_permissions: %i[view_issues])

    result = ConditionalPermProbe.call(server_context: { user: user }, elevated: true).to_h

    assert result[:isError]
    assert_equal RedmineMcpPlugin::Tools::Base::UNAVAILABLE, result[:content].first[:text]
  end

  # The refusal message must not reveal which lock tripped: read-only and
  # missing-permission are indistinguishable to the caller.
  def test_refusal_wording_is_uniform_across_locks
    read_only = WriteProbe.call(server_context: { user: FakeUser.new(allowed: true) }).to_h
    denied    = PermProbe.call(server_context: { user: FakeUser.new(allowed: false) }).to_h

    assert_equal read_only[:content].first[:text], denied[:content].first[:text]
  end

  def test_body_runs_when_locks_pass
    with_read_only_off do
      result = WriteProbe.call(server_context: { user: FakeUser.new(allowed: true) }).to_h

      assert_not result[:isError]
      assert_equal({ created: true }, result[:structuredContent])
    end
  end

  # --- Tool errors stay inside a successful result --------------------------

  def test_tool_error_becomes_an_error_response
    result = ErrorProbe.call(server_context: { user: FakeUser.new(allowed: true) }).to_h

    assert result[:isError]
    assert_equal 'nothing matched', result[:content].first[:text]
  end

  def test_permission_error_becomes_an_error_response
    result = PermissionErrorProbe.call(server_context: { user: FakeUser.new(allowed: true) }).to_h

    assert result[:isError]
    assert_equal 'not permitted', result[:content].first[:text]
  end

  # --- Pagination helpers ---------------------------------------------------

  def test_limit_defaults_to_max_results_and_clamps
    probe = HelperProbe.new(nil)

    assert_equal 100, probe.limit({})
    assert_equal 100, probe.limit('limit' => 5000)
    assert_equal 1, probe.limit('limit' => 0)
  end

  def test_offset_defaults_to_zero_and_clamps
    probe = HelperProbe.new(nil)

    assert_equal 0, probe.offset({})
    assert_equal 0, probe.offset('offset' => -1)
    assert_equal 250, probe.offset('offset' => 250)
  end

  def test_paged_reports_has_more_against_the_total
    probe = HelperProbe.new(nil)

    page = probe.page(total: 10, offset: 0, key: :rows, rows: [1, 2, 3])

    assert_equal 10, page[:total_count]
    assert_equal 3, page[:returned]
    assert page[:has_more]
    assert_equal [1, 2, 3], page[:rows]
  end

  # --- Derived annotations --------------------------------------------------

  def test_read_tool_annotations
    annotations = ReadProbe.to_h[:annotations]

    assert annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
    assert annotations[:idempotentHint]
  end

  def test_write_tool_annotations
    annotations = WriteProbe.to_h[:annotations]

    assert_not annotations[:readOnlyHint]
    assert annotations[:destructiveHint]
    assert_not annotations[:idempotentHint]
  end

  # --- A converted read tool, end to end through a mounted MCP::Server -------

  def test_get_issue_runs_through_the_sdk_server
    server = build_server(User.find(1))

    result = server.handle(tool_call('get_issue', 'id' => 1))[:result]

    assert_not result[:isError]
    assert_equal 1, result[:structuredContent][:id]
    assert_equal 'text', result[:content].first[:type]
  end

  def test_get_issue_is_listed_with_read_only_annotations
    server = build_server(User.find(1))

    tools = server.handle(list_tools)[:result][:tools]
    descriptor = tools.detect { |tool| tool[:name] == 'get_issue' }

    assert descriptor, 'get_issue should be mounted on the server'
    assert descriptor[:annotations][:readOnlyHint]
  end

  # Invisible and nonexistent issues must stay indistinguishable so record
  # existence cannot leak through the error text.
  def test_get_issue_reports_an_invisible_issue_as_not_found
    issue = Issue.find(4)
    issue.update_columns(is_private: true)
    server = build_server(User.find(7))

    result = server.handle(tool_call('get_issue', 'id' => issue.id))[:result]

    assert result[:isError]
    assert_match(/No visible issue/, result[:content].first[:text])
  end

  private

  def build_server(user)
    RedmineMcpPlugin::McpServer.build(
      tools: [RedmineMcpPlugin::Tools::GetIssue],
      server_context: { user: user, auth: { mode: :api_key } }
    )
  end

  def tool_call(name, arguments = {})
    { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: name, arguments: arguments } }
  end

  def list_tools
    { jsonrpc: '2.0', id: 4, method: 'tools/list', params: {} }
  end

  def with_read_only_off
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '0')
    Setting.clear_cache
    yield
  ensure
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '1')
    Setting.clear_cache
  end
end
