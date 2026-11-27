# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers the time-tracking write surface added for ticket 77619: logging hours
# against an issue, discovering the activities a time entry can use, and
# discovering the required and custom fields that must be populated.
# Everything runs through a mounted MCP::Server so the public tool boundary is
# exercised, never the tool bodies directly.
class RedmineMcpPluginTimeTrackingToolsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :time_entries

  def setup
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('read_only' => '1')
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  # --- discovery and annotations -------------------------------------------

  def test_log_time_is_hidden_in_read_only_mode
    names = tools_list(build_server(User.find(2))).map { |t| t[:name] }

    assert_not_includes names, 'log_time'
  end

  def test_log_time_is_listed_when_read_only_is_off
    with_read_only_off do
      names = tools_list(build_server(User.find(2))).map { |t| t[:name] }

      assert_includes names, 'log_time'
    end
  end

  def test_log_time_is_a_non_idempotent_non_destructive_write
    annotations = RedmineMcpPlugin::Tools::LogTime.to_h[:annotations]

    assert_not annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
    assert_not annotations[:idempotentHint]
  end

  def test_list_time_entry_activities_is_a_read_tool
    annotations = RedmineMcpPlugin::Tools::ListTimeEntryActivities.to_h[:annotations]

    assert annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
  end

  def test_list_time_entry_fields_is_a_read_tool
    annotations = RedmineMcpPlugin::Tools::ListTimeEntryFields.to_h[:annotations]

    assert annotations[:readOnlyHint]
    assert_not annotations[:destructiveHint]
  end

  # --- log_time -------------------------------------------------------------

  def test_log_time_logs_as_the_authenticated_user_with_project_defaults
    user = User.find(2)
    project = Project.find_by(identifier: 'ecookbook')

    with_read_only_off do
      result = call_as(user, 'log_time', 'issue_id' => 1, 'hours' => 1.5,
                       'comments' => 'MCP setup')[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      payload = result[:structuredContent]
      entry = TimeEntry.find(payload[:id])

      assert_equal user.id, entry.user_id, 'time is logged for the caller'
      assert_equal user.id, entry.author_id
      assert_equal 1, entry.issue_id
      assert_in_delta 1.5, entry.hours.to_f, 0.001
      assert_equal TimeEntryActivity.default_activity_id(user, project), entry.activity_id
      assert_equal user.today, entry.spent_on
      assert_equal 'MCP setup', entry.comments

      assert_equal entry.id, payload[:id]
      assert_equal user.id, payload[:user][:id]
      assert_equal 'ecookbook', payload[:project_identifier]
      assert_equal entry.activity_id, payload[:activity][:id]
    end
  end

  def test_log_time_logs_against_a_project_without_an_issue
    user = User.find(2)
    project = Project.find_by(identifier: 'ecookbook')

    with_read_only_off do
      result = call_as(user, 'log_time', 'project' => 'ecookbook', 'hours' => 1.5,
                       'comments' => 'Project-level work')[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      payload = result[:structuredContent]
      entry = TimeEntry.find(payload[:id])

      assert_equal user.id, entry.user_id, 'time is logged for the caller'
      assert_equal user.id, entry.author_id
      assert_equal project.id, entry.project_id
      assert_nil entry.issue_id
      assert_in_delta 1.5, entry.hours.to_f, 0.001
      assert_equal TimeEntryActivity.default_activity_id(user, project), entry.activity_id
      assert_equal user.today, entry.spent_on
      assert_equal 'Project-level work', entry.comments

      assert_equal entry.id, payload[:id]
      assert_nil payload[:issue_id]
      assert_equal 'ecookbook', payload[:project_identifier]
    end
  end

  def test_log_time_resolves_a_project_by_numeric_id
    user = User.find(2)
    project = Project.find_by(identifier: 'ecookbook')

    with_read_only_off do
      result = call_as(user, 'log_time', 'project' => project.id, 'hours' => 1)[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      entry = TimeEntry.find(result[:structuredContent][:id])
      assert_equal project.id, entry.project_id
      assert_nil entry.issue_id
    end
  end

  def test_log_time_requires_project_or_issue_id
    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/Provide project or issue_id/, result[:content].first[:text])
    end
  end

  def test_log_time_rejects_an_issue_that_is_not_in_the_given_project
    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'project' => 'onlinestore',
                       'issue_id' => 1, 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/is not in project/, result[:content].first[:text])
    end
  end

  def test_log_time_reports_an_invisible_project_as_not_found
    with_read_only_off do
      result = call_as(User.find(3), 'log_time', 'project' => 'private-child', 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/No visible project/, result[:content].first[:text])
    end
  end

  def test_log_time_refuses_a_project_without_time_tracking
    with_read_only_off do
      result = call_as(User.find(1), 'log_time', 'project' => 'onlinestore', 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/time tracking module is not enabled/, result[:content].first[:text])
    end
  end

  def test_log_time_honors_per_project_authorize_for_a_project_context
    Role.find(4).remove_permission!(:log_time)

    with_read_only_off do
      result = call_as(User.find(3), 'log_time', 'project' => 'subproject1', 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/permission/i, result[:content].first[:text])
    end
  end

  def test_log_time_requires_issue_id_when_redmine_requires_it
    with_settings(:timelog_required_fields => ['issue_id']) do
      with_read_only_off do
        result = call_as(User.find(2), 'log_time', 'project' => 'ecookbook', 'hours' => 1)[:result]

        assert result[:isError]
        assert_match(/Issue cannot be blank/i, result[:content].first[:text])
      end
    end
  end

  def test_log_time_resolves_activity_by_name_and_by_numeric_id
    with_read_only_off do
      by_name = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                        'activity_id' => 'QA')[:result]
      assert_not by_name[:isError], by_name[:content]&.first&.dig(:text)
      assert_equal 11, TimeEntry.find(by_name[:structuredContent][:id]).activity_id

      by_id = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                      'activity_id' => 9)[:result]
      assert_not by_id[:isError], by_id[:content]&.first&.dig(:text)
      assert_equal 9, TimeEntry.find(by_id[:structuredContent][:id]).activity_id
    end
  end

  # With no default activity marked, the project still has active activities,
  # so the refusal must ask for activity_id rather than claim there are none.
  def test_log_time_without_a_default_activity_asks_for_activity_id
    TimeEntryActivity.update_all(is_default: false)
    Role.update_all(default_time_entry_activity_id: nil)

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1)[:result]

      assert result[:isError]
      text = result[:content].first[:text]
      assert_match(/no default time entry activity/, text)
      assert_match(/activity_id/, text)
      assert_match(/list_time_entry_activities/, text)
      assert_includes text, 'Design'
    end
  end

  def test_log_time_honors_an_explicit_spent_on_date
    spent_on = Date.yesterday

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'spent_on' => spent_on.iso8601)[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      assert_equal spent_on, TimeEntry.find(result[:structuredContent][:id]).spent_on
    end
  end

  def test_log_time_rejects_an_invalid_spent_on_date
    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'spent_on' => '2026-02-30')[:result]

      assert result[:isError]
      assert_match(/YYYY-MM-DD/, result[:content].first[:text])
    end
  end

  def test_log_time_rejects_an_activity_not_available_on_the_project
    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'activity_id' => 14)[:result]

      assert result[:isError]
      assert_match(/No active time entry activity/, result[:content].first[:text])
    end
  end

  def test_log_time_reports_an_invisible_issue_as_not_found
    with_read_only_off do
      # Issue 6 belongs to the private project 5, which dlopper (3) cannot see.
      result = call_as(User.find(3), 'log_time', 'issue_id' => 6, 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/No visible issue/, result[:content].first[:text])
    end
  end

  # dlopper (3) has log_time through the Developer role on project 1, so the tool
  # stays discoverable. On the public project 3 they are only a non-member;
  # stripping log_time from the Non member role leaves the per-project
  # authorize! refusal as the gate that trips.
  def test_log_time_honors_per_project_authorize
    Role.find(4).remove_permission!(:log_time)

    with_read_only_off do
      result = call_as(User.find(3), 'log_time', 'issue_id' => 5, 'hours' => 1)[:result]

      assert result[:isError]
      assert_match(/permission/i, result[:content].first[:text])
    end
  end

  def test_log_time_saves_custom_fields_by_id_and_name
    phase = TimeEntryCustomField.create!(name: 'MCP Phase', field_format: 'list',
                                         possible_values: %w[Build Review])
    ticket = TimeEntryCustomField.create!(name: 'MCP Ticket', field_format: 'string')

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'custom_fields' => { phase.id.to_s => 'Build', 'MCP Ticket' => 'ABC-1' })[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      entry = TimeEntry.find(result[:structuredContent][:id])

      assert_equal 'Build', entry.custom_field_value(phase)
      assert_equal 'ABC-1', entry.custom_field_value(ticket)

      payload_fields = result[:structuredContent][:custom_fields].index_by { |field| field[:name] }
      assert_equal 'Build', payload_fields['MCP Phase'][:value]
      assert_equal 'ABC-1', payload_fields['MCP Ticket'][:value]
    end
  end

  def test_log_time_normalizes_boolean_custom_field_values
    overtime = TimeEntryCustomField.create!(name: 'MCP Overtime', field_format: 'bool')

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'custom_fields' => { overtime.id.to_s => true })[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      entry = TimeEntry.find(result[:structuredContent][:id])

      assert_equal '1', entry.custom_field_value(overtime)
    end
  end

  def test_log_time_rejects_an_invalid_boolean_custom_field
    overtime = TimeEntryCustomField.create!(name: 'MCP Overtime', field_format: 'bool')

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'custom_fields' => { overtime.id.to_s => 'maybe' })[:result]

      assert result[:isError]
      assert_match(/expects a boolean value/, result[:content].first[:text])
    end
  end

  def test_log_time_requires_required_custom_field
    required = TimeEntryCustomField.create!(name: 'MCP Required', field_format: 'string',
                                            is_required: true)

    with_read_only_off do
      missing = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1)[:result]
      assert missing[:isError]
      assert_match(/Mcp required cannot be blank/i, missing[:content].first[:text])

      supplied = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                         'custom_fields' => { required.id.to_s => 'present' })[:result]
      assert_not supplied[:isError], supplied[:content]&.first&.dig(:text)
    end
  end

  def test_log_time_requires_comments_when_configured
    with_settings(:timelog_required_fields => ['comments']) do
      with_read_only_off do
        missing = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1)[:result]
        assert missing[:isError]
        assert_match(/Comment cannot be blank/i, missing[:content].first[:text])

        supplied = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                           'comments' => 'required note')[:result]
        assert_not supplied[:isError], supplied[:content]&.first&.dig(:text)
      end
    end
  end

  def test_log_time_rejects_an_unavailable_custom_field
    hidden = TimeEntryCustomField.create!(name: 'MCP Hidden', field_format: 'string',
                                          visible: false, role_ids: [1])

    with_read_only_off do
      [hidden.id.to_s, 'No such field'].each do |key|
        result = call_as(User.find(3), 'log_time', 'issue_id' => 1, 'hours' => 1,
                         'custom_fields' => { key => 'value' })[:result]

        assert result[:isError]
        assert_match(/Unknown or non-editable time entry custom field/,
                     result[:content].first[:text])
      end
    end
  end

  def test_log_time_accepts_multiple_values_for_a_multiple_custom_field
    tags = TimeEntryCustomField.create!(name: 'MCP Tags', field_format: 'list',
                                        possible_values: %w[one two three], multiple: true)

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'custom_fields' => { tags.id.to_s => %w[one three] })[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      entry = TimeEntry.find(result[:structuredContent][:id])

      assert_equal %w[one three], entry.custom_field_value(tags).sort
    end
  end

  def test_log_time_rejects_an_array_for_a_single_custom_field
    field = TimeEntryCustomField.create!(name: 'MCP Single', field_format: 'string')

    with_read_only_off do
      result = call_as(User.find(2), 'log_time', 'issue_id' => 1, 'hours' => 1,
                       'custom_fields' => { field.id.to_s => %w[one two] })[:result]

      assert result[:isError]
      assert_match(/accepts a single value/, result[:content].first[:text])
    end
  end

  # --- list_time_entry_fields -----------------------------------------------

  def test_list_time_entry_fields_lists_required_and_possible_values
    phase = TimeEntryCustomField.create!(name: 'MCP Phase', description: 'Delivery phase',
                                         field_format: 'list', possible_values: %w[Build Review],
                                         is_required: true)
    overtime = TimeEntryCustomField.create!(name: 'MCP Overtime', field_format: 'bool',
                                            default_value: '0')

    with_settings(:timelog_required_fields => ['comments']) do
      result = call_as(User.find(2), 'list_time_entry_fields', 'issue_id' => 1)[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      payload = result[:structuredContent]

      assert_equal 'ecookbook', payload[:project_identifier]
      assert_equal 1, payload[:issue_id]
      assert_includes payload[:required_fields], 'issue_id'
      assert_includes payload[:required_fields], 'hours'
      assert_includes payload[:required_fields], 'comments'

      fields = payload[:custom_fields].index_by { |field| field[:name] }
      assert_equal 'list', fields['MCP Phase'][:field_format]
      assert fields['MCP Phase'][:is_required]
      assert_equal [{ label: 'Build', value: 'Build' }, { label: 'Review', value: 'Review' }],
                   fields['MCP Phase'][:possible_values]

      assert_equal 'bool', fields['MCP Overtime'][:field_format]
      assert_equal %w[1 0], fields['MCP Overtime'][:possible_values].map { |value| value[:value] }
      assert_equal '0', fields['MCP Overtime'][:default_value]

      assert_equal [{ id: phase.id, name: 'MCP Phase', field_format: 'list' }],
                   payload[:required_custom_fields]
      assert_equal overtime.id, fields['MCP Overtime'][:id]
    end
  end

  def test_list_time_entry_fields_resolves_a_project_without_an_issue
    TimeEntryCustomField.create!(name: 'MCP Project Field', field_format: 'string')

    result = call_as(User.find(2), 'list_time_entry_fields', 'project' => 'ecookbook')[:result]

    assert_not result[:isError], result[:content]&.first&.dig(:text)
    payload = result[:structuredContent]
    assert_equal 'ecookbook', payload[:project_identifier]
    assert_nil payload[:issue_id]
    assert_includes payload[:required_fields], 'hours'
    assert_not_includes payload[:required_fields], 'issue_id'
    assert_includes payload[:custom_fields].map { |field| field[:name] }, 'MCP Project Field'
  end

  def test_list_time_entry_fields_requires_issue_id_when_redmine_requires_it
    with_settings(:timelog_required_fields => ['issue_id']) do
      result = call_as(User.find(2), 'list_time_entry_fields', 'project' => 'ecookbook')[:result]

      assert_not result[:isError], result[:content]&.first&.dig(:text)
      assert_includes result[:structuredContent][:required_fields], 'issue_id'
    end
  end

  def test_list_time_entry_fields_filters_role_scoped_fields
    TimeEntryCustomField.create!(name: 'MCP Manager', field_format: 'string',
                                 visible: false, role_ids: [1])
    TimeEntryCustomField.create!(name: 'MCP Developer', field_format: 'string',
                                 visible: false, role_ids: [2])

    result = call_as(User.find(3), 'list_time_entry_fields', 'project' => 'ecookbook')[:result]

    assert_not result[:isError], result[:content]&.first&.dig(:text)
    names = result[:structuredContent][:custom_fields].map { |field| field[:name] }
    assert_includes names, 'MCP Developer'
    assert_not_includes names, 'MCP Manager'
  end

  def test_list_time_entry_fields_requires_project_or_issue
    result = call_as(User.find(2), 'list_time_entry_fields')[:result]

    assert result[:isError]
    assert_match(/Provide project or issue_id/, result[:content].first[:text])
  end

  def test_list_time_entry_fields_refuses_an_invisible_project
    result = call_as(User.find(3), 'list_time_entry_fields', 'project' => 'private-child')[:result]

    assert result[:isError]
    assert_match(/No visible project/, result[:content].first[:text])
  end

  def test_list_time_entry_fields_refuses_a_project_without_time_tracking
    result = call_as(User.find(1), 'list_time_entry_fields', 'project' => 'onlinestore')[:result]

    assert result[:isError]
    assert_match(/time tracking module is not enabled/, result[:content].first[:text])
  end

  # --- list_time_entry_activities ------------------------------------------

  def test_list_time_entry_activities_lists_shared_activities_by_default
    result = call_as(User.find(2), 'list_time_entry_activities')[:result]

    assert_not result[:isError], result[:content]&.first&.dig(:text)
    payload = result[:structuredContent]
    names = payload[:activities].map { |activity| activity[:name] }

    assert_nil payload[:project_identifier]
    assert_includes names, 'Design'
    assert_includes names, 'Development'
    assert_includes names, 'QA'
    assert_not_includes names, 'Inactive Activity'
    assert_equal ['Development'], payload[:activities].select { |a| a[:is_default] }.map { |a| a[:name] }
  end

  def test_list_time_entry_activities_includes_a_projects_own_activities
    project = Project.find_by(identifier: 'ecookbook')
    project.time_entry_activities.create!(name: 'MCP Review', active: true)

    result = call_as(User.find(2), 'list_time_entry_activities', 'project' => 'ecookbook')[:result]

    assert_not result[:isError], result[:content]&.first&.dig(:text)
    payload = result[:structuredContent]
    names = payload[:activities].map { |activity| activity[:name] }

    assert_equal 'ecookbook', payload[:project_identifier]
    assert_includes names, 'MCP Review'
    assert_includes names, 'Development'
  end

  def test_list_time_entry_activities_refuses_an_invisible_project
    result = call_as(User.find(3), 'list_time_entry_activities', 'project' => 'private-child')[:result]

    assert result[:isError]
    assert_match(/No visible project/, result[:content].first[:text])
  end

  def test_list_time_entry_activities_refuses_a_project_without_time_tracking
    result = call_as(User.find(1), 'list_time_entry_activities', 'project' => 'onlinestore')[:result]

    assert result[:isError]
    assert_match(/time tracking module is not enabled/, result[:content].first[:text])
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
