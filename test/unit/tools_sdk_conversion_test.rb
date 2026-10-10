# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Proves migration slice 04: every registered tool inherits the SDK-backed
# Tools::Base, declares a schema the SDK accepts, and runs only through
# MCP::Server#handle. The write gate, the per-project authorize! refusal, and
# SDK-side argument validation are all exercised through a mounted server.
class RedmineMcpPluginToolsSdkConversionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :journals, :wikis, :wiki_pages, :wiki_contents

  ALL_TOOLS = RedmineMcpPlugin::Registry.all

  def setup
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '1')
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  # --- Conversion invariants ------------------------------------------------

  def test_every_registered_tool_inherits_the_sdk_base
    ALL_TOOLS.each do |tool|
      assert_operator tool, :<, RedmineMcpPlugin::Tools::Base, "#{tool} must inherit Tools::Base"
      assert_operator tool, :<, MCP::Tool, "#{tool} must be an MCP::Tool"
    end
  end

  # Expected to be sixteen (12 read + 4 write); a tool silently dropped from or
  # added to the registry would be a security-relevant regression, so the count
  # is pinned.
  def test_registry_exposes_all_sixteen_tools
    assert_equal 16, ALL_TOOLS.size
    assert_equal 4, ALL_TOOLS.count(&:write?)
  end

  # Each tool's descriptor comes from the SDK DSL now. Constructing to_h forces
  # the input schema through the SDK's 2020-12 metaschema validation, so a
  # malformed schema would raise here.
  def test_every_tool_declares_name_schema_and_annotations_through_the_dsl
    ALL_TOOLS.each do |tool|
      descriptor = tool.to_h

      assert descriptor[:name].present?, "#{tool} must declare a tool_name"
      assert descriptor[:description].present?, "#{tool} must declare a description"
      assert_equal 'object', descriptor[:inputSchema][:type].to_s
      annotations = descriptor[:annotations]
      assert_includes [true, false], annotations[:readOnlyHint]
      assert_includes [true, false], annotations[:destructiveHint]
    end
  end

  # The read-only hint must track the write flag so the advisory the client
  # reads cannot drift from the gate that actually blocks the call.
  def test_write_tools_carry_a_non_read_only_hint
    write_tools = ALL_TOOLS.select(&:write?)

    assert_equal %w[create_issue add_issue_note create_version create_wiki_page].sort,
                 write_tools.map { |t| t.to_h[:name] }.sort
    write_tools.each do |tool|
      assert_not tool.to_h[:annotations][:readOnlyHint], "#{tool} is a write tool"
    end
  end

  # --- Discovery and execution through a mounted server ---------------------

  def test_read_tools_are_listed_and_runnable_through_the_server
    server = build_server(User.find(1))

    names = tools_list(server).map { |t| t[:name] }
    assert_includes names, 'list_projects'

    result = call(server, 'list_projects')[:result]
    assert_not result[:isError]
    assert result[:structuredContent][:projects].present?
  end

  def test_write_tools_are_hidden_and_refused_in_read_only_mode
    server = build_server(User.find(1))

    assert_not_includes tools_list(server).map { |t| t[:name] }, 'create_issue',
                        'a write tool must not be discoverable in read-only mode'

    # Even reached directly, the execution lock refuses with the uniform wording.
    result = RedmineMcpPlugin::Tools::CreateIssue.call(
      server_context: { user: User.find(1) }, project: 'ecookbook', subject: 'x'
    ).to_h
    assert result[:isError]
    assert_equal RedmineMcpPlugin::Tools::Base::UNAVAILABLE, result[:content].first[:text]
  end

  # authorize! stays enforced per project: a user without :add_issues on the
  # target project is refused even with read-only off and the global permission.
  def test_create_issue_honors_per_project_authorize
    with_read_only_off do
      # dlopper can see subproject2 but has no :add_issues there, so fetch_project
      # succeeds and authorize! is the gate that refuses.
      server = build_server(User.find(3))
      result = call(server, 'create_issue', 'project' => 'subproject2', 'subject' => 'Nope')[:result]

      assert result[:isError]
      assert_match(/permission/i, result[:content].first[:text])
    end
  end

  # --- SDK-side validation replaces the hand-rolled validator ---------------

  # The SDK reports a schema violation as an isError tool result, not a
  # JSON-RPC error, and the tool body never runs.
  def test_sdk_rejects_arguments_that_violate_the_schema
    server = build_server(User.find(1))

    missing_required = call(server, 'get_project')[:result]
    assert missing_required[:isError], 'a missing required property must be rejected by the SDK'

    unknown_property = call(server, 'get_project', 'project' => 'ecookbook', 'bogus' => 1)[:result]
    assert unknown_property[:isError], 'additionalProperties:false must reject unknown keys'
  end

  private

  def build_server(user)
    RedmineMcpPlugin::McpServer.build(
      tools: RedmineMcpPlugin::Registry.all.select { |tool| tool.available_to?(user, oauth_scopes: nil) },
      server_context: { user: user, auth: { mode: :api_key } }
    )
  end

  def tools_list(server)
    server.handle({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })[:result][:tools]
  end

  def call(server, name, arguments = {})
    server.handle({ jsonrpc: '2.0', id: 2, method: 'tools/call',
                    params: { name: name, arguments: arguments } })
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
