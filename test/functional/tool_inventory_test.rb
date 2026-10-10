# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers the read-only tool inventory decided in ticket 04: the new catalog,
# version, and group tools; the reshaped get_issue payload; the stripped
# enumerations; and the two new non-destructive write tools. Everything runs
# through a mounted MCP::Server so the public tool boundary is exercised, never
# the tool bodies directly.
class RedmineMcpPluginToolInventoryTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :groups_users, :issues, :issue_statuses, :trackers, :enumerations,
           :enabled_modules, :journals, :journal_details, :versions, :wikis,
           :wiki_pages, :wiki_contents

  def setup
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '1')
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  # --- list_statuses --------------------------------------------------------

  def test_list_statuses_returns_the_catalog_with_is_closed
    result = call_as(User.find(1), 'list_statuses')[:result]

    assert_not result[:isError]
    statuses = result[:structuredContent][:statuses]
    assert statuses.present?
    assert(statuses.all? { |s| s.key?(:id) && s.key?(:name) && [true, false].include?(s[:is_closed]) })
  end

  # --- list_enumerations no longer carries statuses -------------------------

  def test_list_enumerations_drops_statuses_and_keeps_trackers_and_priorities
    result = call_as(User.find(1), 'list_enumerations')[:result]

    assert_not result[:isError]
    payload = result[:structuredContent]
    assert payload[:trackers].present?
    assert payload[:priorities].present?
    assert_not payload.key?(:issue_statuses), 'statuses moved to list_statuses'
  end

  # --- list_versions --------------------------------------------------------

  def test_list_versions_lists_a_projects_versions
    result = call_as(User.find(1), 'list_versions', 'project' => 'ecookbook')[:result]

    assert_not result[:isError]
    names = result[:structuredContent][:versions].map { |v| v[:name] }
    assert_includes names, '1.0'
  end

  def test_list_versions_omits_time_totals_unless_requested
    result = call_as(User.find(1), 'list_versions', 'project' => 'ecookbook')[:result]

    assert(result[:structuredContent][:versions].none? { |v| v.key?(:spent_hours) })
  end

  # --- get_group: non-admin read path, builtin excluded, typed members ------

  def test_get_group_resolves_by_name_with_typed_members
    result = call_as(User.find(1), 'get_group', 'group' => 'A Team', 'include_users' => true)[:result]

    assert_not result[:isError]
    group = result[:structuredContent]
    assert_equal 'Group', group[:type]
    assert group[:users].present?
    assert(group[:users].all? { |u| u[:type] == 'User' && u.key?(:id) })
    assert_includes group[:users].map { |u| u[:id] }, 8
  end

  def test_get_group_omits_users_by_default
    result = call_as(User.find(1), 'get_group', 'group' => 'A Team')[:result]

    assert_not result[:isError]
    assert_not result[:structuredContent].key?(:users)
  end

  # A builtin group must be unreachable: Group.givable excludes it, so the
  # lookup fails with the same not-found wording as a missing group.
  def test_get_group_does_not_resolve_builtin_groups
    result = call_as(User.find(1), 'get_group', 'group' => 'Non member users')[:result]

    assert result[:isError]
    assert_match(/No group matching/, result[:content].first[:text])
  end

  # --- get_issue reshaped payload -------------------------------------------

  def test_get_issue_returns_typed_identities_and_closed_on_and_status_object
    result = call_as(User.find(1), 'get_issue', 'id' => 1)[:result]

    assert_not result[:isError]
    payload = result[:structuredContent]
    assert_equal 'User', payload[:author][:type]
    assert payload[:author][:id].present?
    assert payload[:status].key?(:is_closed)
    assert payload.key?(:closed_on)
  end

  def test_get_issue_journal_actor_is_a_typed_identity
    result = call_as(User.find(1), 'get_issue', 'id' => 1, 'include_journals' => true)[:result]

    journals = result[:structuredContent][:journals]
    assert journals.present?, 'issue 1 has journals'
    assert(journals.all? { |j| j[:user].nil? || j[:user][:type] == 'User' })
  end

  def test_get_issue_includes_are_opt_in
    without = call_as(User.find(1), 'get_issue', 'id' => 1)[:result][:structuredContent]
    assert_not without.key?(:relations)
    assert_not without.key?(:children)
    assert_not without.key?(:attachments)
    # attachments_count is part of the normal shape even when the metadata page
    # is not requested, so a caller knows whether paging it is worthwhile.
    assert without.key?(:attachments_count)

    with = call_as(User.find(1), 'get_issue', 'id' => 1, 'include_relations' => true,
                   'include_children' => true, 'include_attachments' => true)[:result][:structuredContent]
    assert with.key?(:relations)
    assert with.key?(:children)
    assert with.key?(:attachments)
    assert with[:attachments].key?(:total_count), 'the attachments include is a pagination envelope'
    assert with[:attachments].key?(:items)
  end

  # include_spent_hours requires view_time_entries; the override folds it into
  # the invocation's required permissions.
  def test_get_issue_spent_hours_demands_view_time_entries
    assert_includes RedmineMcpPlugin::Tools::GetIssue.required_permissions('include_spent_hours' => true),
                    :view_time_entries
    assert_includes RedmineMcpPlugin::Tools::GetIssue.required_permissions('include_watchers' => true),
                    :view_issue_watchers
    assert_not_includes RedmineMcpPlugin::Tools::GetIssue.required_permissions({}), :view_time_entries
  end

  # --- new write tools: discovery and annotations ---------------------------

  def test_new_write_tools_are_hidden_in_read_only_mode
    names = tools_list(build_server(User.find(1))).map { |t| t[:name] }

    assert_not_includes names, 'create_version'
    assert_not_includes names, 'create_wiki_page'
  end

  def test_create_wiki_page_advertises_idempotent_non_destructive_write
    annotations = RedmineMcpPlugin::Tools::CreateWikiPage.to_h[:annotations]

    assert_not annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
    assert annotations[:idempotentHint], 'an upsert is idempotent'
  end

  def test_create_version_is_a_non_idempotent_non_destructive_write
    annotations = RedmineMcpPlugin::Tools::CreateVersion.to_h[:annotations]

    assert_not annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
    assert_not annotations[:idempotentHint], 'create-only is not idempotent'
  end

  # --- new write tools: execution with read-only off ------------------------

  def test_create_version_creates_when_permitted
    with_read_only_off do
      result = call_as(User.find(1), 'create_version', 'project' => 'ecookbook', 'name' => 'MCP Milestone')[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      assert result[:structuredContent][:id].present?
      assert_equal 'open', result[:structuredContent][:status]
    end
  end

  def test_create_wiki_page_upserts_when_permitted
    with_read_only_off do
      result = call_as(User.find(1), 'create_wiki_page',
                       'project' => 'ecookbook', 'title' => 'McpSurfaceRefactor', 'text' => 'hello')[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      assert result[:structuredContent][:created]
      assert_equal 'McpSurfaceRefactor', result[:structuredContent][:title]
    end
  end

  # create_wiki_page is gated on edit_wiki_pages per project, not a global role.
  # dlopper (3) is a member of ecookbook (wiki module enabled), so the module gate
  # passes; stripping edit_wiki_pages from their role leaves only the per-project
  # permission denial, which is what this exercises.
  def test_create_wiki_page_honors_per_project_authorize
    Role.find(2).remove_permission!(:edit_wiki_pages)

    with_read_only_off do
      result = call_as(User.find(3), 'create_wiki_page',
                       'project' => 'ecookbook', 'title' => 'Nope', 'text' => 'x')[:result]

      assert result[:isError]
      assert_match(/permission/i, result[:content].first[:text])
    end
  end

  private

  def build_server(user)
    RedmineMcpPlugin::McpServer.build(
      tools: RedmineMcpPlugin::Registry.all.select { |tool| tool.available_to?(user, oauth_scopes: nil) },
      server_context: { user: user, auth: { mode: :api_key } }
    )
  end

  def call_as(user, name, arguments = {})
    build_server(user).handle(
      { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: name, arguments: arguments } }
    )
  end

  def tools_list(server)
    server.handle({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })[:result][:tools]
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
