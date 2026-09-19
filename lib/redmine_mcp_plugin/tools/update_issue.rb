# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class UpdateIssue < Tool
      tool 'update_issue',
           title: 'Update issue',
           description: 'Update a visible issue by id.',
           permission: :edit_issues,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'id' => { 'type' => 'integer', 'description' => 'Issue id.' },
               'subject' => { 'type' => 'string', 'description' => 'New issue subject.' },
               'description' => { 'type' => 'string', 'description' => 'New issue description.' },
               'tracker' => { 'type' => 'string', 'description' => 'Tracker name.' },
               'priority' => { 'type' => 'string', 'description' => 'Priority name.' },
               'status' => { 'type' => 'string', 'description' => 'Target status name.' },
               'done_ratio' => { 'type' => 'integer', 'description' => 'Completion percentage from 0 to 100.' },
               'assigned_to' => { 'type' => 'string', 'description' => 'Login of the assignee, or "none" to unassign.' },
               'notes' => { 'type' => 'string', 'description' => 'Optional comment to add with the update.' },
               'private' => { 'type' => 'boolean', 'description' => 'Mark the note private when notes are provided.' }
             },
             'required' => %w[id],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue = Issue.visible(user).find_by(id: arguments['id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['id'].inspect}" if issue.nil?

        authorize!(:edit_issues, issue.project)

        attributes = {}

        if arguments.key?('subject')
          subject = arguments['subject'].to_s.strip
          raise ToolError, 'subject must not be empty' if subject.empty?

          attributes['subject'] = subject
        end

        if arguments.key?('description')
          attributes['description'] = arguments['description'].to_s
        end

        if arguments.key?('tracker')
          tracker_name = arguments['tracker'].to_s
          tracker = issue.project.trackers.find_by(name: tracker_name)
          raise ToolError, "Project #{issue.project.identifier} has no tracker named #{tracker_name.inspect}" if tracker.nil?

          attributes['tracker_id'] = tracker.id
        end

        if arguments.key?('priority')
          priority_name = arguments['priority'].to_s
          priority = IssuePriority.active.find_by(name: priority_name)
          raise ToolError, "No active priority named #{priority_name.inspect}" if priority.nil?

          attributes['priority_id'] = priority.id
        end

        if arguments.key?('status')
          status_name = arguments['status'].to_s
          status = IssueStatus.find_by(name: status_name)
          raise ToolError, "Project #{issue.project.identifier} has no status named #{status_name.inspect}" if status.nil?

          unless issue.new_statuses_allowed_to(user).map(&:id).include?(status.id)
            raise ToolError, "Status #{status_name.inspect} is not allowed for issue #{issue.id}"
          end

          attributes['status_id'] = status.id
        end

        if arguments.key?('done_ratio')
          done_ratio = arguments['done_ratio'].to_i
          raise ToolError, 'done_ratio must be between 0 and 100' unless (0..100).cover?(done_ratio)

          attributes['done_ratio'] = done_ratio
        end

        if arguments.key?('assigned_to')
          assigned_value = arguments['assigned_to'].to_s.strip
          if assigned_value.empty? || assigned_value.casecmp('none').zero?
            attributes['assigned_to_id'] = nil
          else
            assignee = issue.project.assignable_users.find_by(login: assigned_value)
            raise ToolError, "#{assigned_value.inspect} is not an assignable user on #{issue.project.identifier}" if assignee.nil?

            attributes['assigned_to_id'] = assignee.id
          end
        end

        if arguments.key?('notes')
          notes = arguments['notes'].to_s
          raise ToolError, 'notes must not be empty' if notes.strip.empty?

          issue.init_journal(user, notes)

          if arguments['private']
            authorize!(:set_notes_private, issue.project)
            issue.private_notes = true
          end
        end

        issue.safe_attributes = attributes unless attributes.empty?
        raise ToolError, "Could not update issue: #{issue.errors.full_messages.join('; ')}" unless issue.save

        {
          id: issue.id,
          subject: issue.subject,
          project_identifier: issue.project.identifier,
          status: issue.status&.name,
          tracker: issue.tracker&.name,
          priority: issue.priority&.name,
          assigned_to_id: issue.assigned_to_id,
          done_ratio: issue.done_ratio,
          updated_on: iso(issue.updated_on)
        }
      end
    end
  end
end
