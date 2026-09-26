# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class CreateIssue < Tool
      include IssueAttributes

      tool 'create_issue',
           title: 'Create issue',
           description: 'Create a new issue in a project.',
           permission: :add_issues,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => %w[string integer],
                             'description' => 'Project identifier or numeric id.' },
               'subject' => { 'type' => 'string', 'description' => 'Issue subject.' },
               'description' => { 'type' => 'string' },
               'tracker' => { 'type' => 'string', 'description' => 'Tracker name. Defaults to the project default.' },
               'priority' => { 'type' => 'string', 'description' => 'Priority name. Defaults to the Redmine default.' },
               'status' => { 'type' => 'string',
                             'description' => 'Status name. Defaults to the tracker default. ' \
                                              'Must be allowed by the workflow for new issues.' },
               'assigned_to' => { 'type' => 'string', 'description' => 'Login of the user to assign to.' },
               'category' => { 'type' => 'string', 'description' => 'Issue category name in the project.' },
               'fixed_version' => { 'type' => 'string', 'description' => 'Target version name. Must be open.' },
               'parent_issue_id' => { 'type' => 'integer',
                                      'description' => 'Parent issue id. Requires the manage_subtasks permission.' }
             },
             'required' => %w[project subject],
             'additionalProperties' => false
           }

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

        if (status_name = arguments['status'].presence)
          attributes['status_id'] = status_id_for(issue, status_name)
        end

        if (category_name = arguments['category'].presence)
          attributes['category_id'] = category_id_for(issue, category_name)
        end

        if (version_name = arguments['fixed_version'].presence)
          attributes['fixed_version_id'] = fixed_version_id_for(issue, version_name)
        end

        if (parent_id = arguments['parent_issue_id'].presence)
          attributes['parent_issue_id'] = parent_issue_id_for(issue, parent_id)
        end

        issue.safe_attributes = attributes
        ensure_applied!(issue, attributes)
        raise ToolError, "Could not create issue: #{issue.errors.full_messages.join('; ')}" unless issue.save

        { id: issue.id, subject: issue.subject, project_identifier: project.identifier,
          status: issue.status&.name, tracker: issue.tracker&.name, category: issue.category&.name,
          fixed_version: issue.fixed_version&.name, parent_id: issue.parent_id, created_on: iso(issue.created_on) }
      end
    end
  end
end
