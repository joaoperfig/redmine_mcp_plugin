# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class CreateIssue < Base
      tool_name 'create_issue'
      title 'Create issue'
      description 'Create a new issue in a project.'
      permission :add_issues
      write true
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id.' },
          'subject' => { 'type' => 'string', 'description' => 'Issue subject.' },
          'description' => { 'type' => 'string' },
          'tracker' => { 'type' => 'string', 'description' => 'Tracker name. Defaults to the project default.' },
          'priority' => { 'type' => 'string', 'description' => 'Priority name. Defaults to the Redmine default.' },
          'assigned_to' => { 'type' => 'string', 'description' => 'Login of the user to assign to.' },
          'custom_fields' => {
            'type' => 'array',
            'description' => 'Custom field values, each naming the field by id or name. Use ' \
                             'list_issue_custom_fields to see the fields, required flags and allowed values.',
            'items' => {
              'type' => 'object',
              'properties' => {
                'id' => { 'type' => 'integer', 'description' => 'Custom field id.' },
                'name' => { 'type' => 'string', 'description' => 'Custom field name.' },
                'value' => { 'type' => %w[string array], 'items' => { 'type' => 'string' },
                             'description' => 'The value, or the label of an allowed value. ' \
                                              'An array for multi-value fields.' }
              },
              'required' => %w[value],
              'additionalProperties' => false
            }
          }
        },
        'required' => %w[project subject],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        authorize!(:add_issues, project)

        issue = Issue.new(project: project, author: user)
        attributes = { 'subject' => arguments['subject'].to_s,
                       'description' => arguments['description'].to_s }

        if (tracker_name = arguments['tracker'].presence)
          tracker = project.trackers.find_by(name: tracker_name.to_s)
          raise ToolError, "Project #{project.identifier} has no tracker named #{tracker_name.inspect}" if tracker.nil?

          attributes['tracker_id'] = tracker.id
        end

        if (priority_name = arguments['priority'].presence)
          priority = IssuePriority.active.find_by(name: priority_name.to_s)
          raise ToolError, "No active priority named #{priority_name.inspect}" if priority.nil?

          attributes['priority_id'] = priority.id
        end

        if (login = arguments['assigned_to'].presence)
          assignee = project.assignable_users.find_by(login: login.to_s)
          raise ToolError, "#{login.inspect} is not an assignable user on #{project.identifier}" if assignee.nil?

          attributes['assigned_to_id'] = assignee.id
        end

        issue.safe_attributes = attributes
        # Resolved after the tracker is set: the settable fields depend on it.
        if (entries = arguments['custom_fields'].presence)
          issue.safe_attributes = { 'custom_field_values' => IssueCustomFields.resolve(issue, user, entries) }
        end
        raise ToolError, "Could not create issue: #{issue.errors.full_messages.join('; ')}" unless issue.save

        { id: issue.id, subject: issue.subject, project_identifier: project.identifier,
          status: issue.status&.name, tracker: issue.tracker&.name, created_on: iso(issue.created_on),
          custom_fields: visible_custom_fields(issue) }
      end

      # Same visibility rule as get_issue: core hides fields the roles cannot see.
      def visible_custom_fields(issue)
        issue.visible_custom_field_values(user).map do |value|
          { id: value.custom_field_id, name: value.custom_field.name, value: value.value }
        end
      end
    end
  end
end
