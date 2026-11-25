# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class CreateTimeEntry < Base
      tool_name 'create_time_entry'
      title 'Log time entry'
      description 'Log spent time on an issue or project in Redmine.'
      permission :log_time
      write true
      input_schema(
        'type' => 'object',
        'properties' => {
          'issue_id' => { 'type' => 'integer', 'description' => 'Numeric issue ID to log time against.' },
          'project' => { 'type' => %w[string integer], 'description' => 'Project identifier or numeric ID (required if issue_id is omitted).' },
          'hours' => { 'type' => 'number', 'description' => 'Number of hours spent (e.g. 1.5, 2).' },
          'activity' => { 'type' => %w[string integer], 'description' => 'Time tracking activity name (e.g. "Development", "Documentation", "Testing & QA") or integer activity ID.' },
          'comments' => { 'type' => 'string', 'description' => 'Short description or comment on the work done.' },
          'spent_on' => { 'type' => 'string', 'description' => 'Date when work was performed (YYYY-MM-DD). Defaults to today.' },
          'user_id' => { 'type' => 'integer', 'description' => 'User ID to log time for (defaults to authenticated user). Logging for other users requires admin or log_time_for_other_users permission.' }
        },
        'required' => %w[hours activity],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        issue = nil
        project = nil

        if arguments['issue_id'].present?
          issue = Issue.visible(user).find_by(id: arguments['issue_id'].to_i)
          raise ToolError, "No visible issue with id #{arguments['issue_id'].inspect}" if issue.nil?

          project = issue.project
        elsif arguments['project'].present?
          project = fetch_project(arguments['project'])
        else
          raise ToolError, 'Either issue_id or project must be provided'
        end

        authorize!(:log_time, project)

        hours = arguments['hours'].to_f
        raise ToolError, 'hours must be greater than 0' if hours <= 0

        activity = resolve_activity(project, arguments['activity'])

        target_user = user
        if arguments['user_id'].present? && arguments['user_id'].to_i != user.id
          if user.admin? || user.allowed_to?(:log_time_for_other_users, project)
            target_user = User.find_by(id: arguments['user_id'].to_i)
            raise ToolError, "User with id #{arguments['user_id']} not found" if target_user.nil?
          else
            raise ToolError, 'You do not have permission to log time for other users'
          end
        end

        spent_on = if arguments['spent_on'].present?
                     begin
                       Date.parse(arguments['spent_on'].to_s)
                     rescue ArgumentError
                       raise ToolError, "Invalid date format for spent_on: #{arguments['spent_on'].inspect} (expected YYYY-MM-DD)"
                     end
                   else
                     user.today
                   end

        time_entry = TimeEntry.new(
          project: project,
          issue: issue,
          author: user,
          user: target_user,
          spent_on: spent_on,
          hours: hours,
          activity: activity,
          comments: arguments['comments'].to_s.strip
        )

        raise ToolError, "Could not log time: #{time_entry.errors.full_messages.join('; ')}" unless time_entry.save

        {
          id: time_entry.id,
          project: { id: project.id, identifier: project.identifier, name: project.name },
          issue_id: issue&.id,
          user: { id: target_user.id, name: target_user.name },
          hours: time_entry.hours,
          activity: { id: activity.id, name: activity.name },
          comments: time_entry.comments,
          spent_on: time_entry.spent_on.to_s,
          created_on: iso(time_entry.created_on)
        }
      end

      def resolve_activity(project, activity_arg)
        activities = project.activities
        if activity_arg.to_s =~ /^\d+$/
          act = activities.find_by(id: activity_arg.to_i) || TimeEntryActivity.shared.active.find_by(id: activity_arg.to_i)
        else
          act = activities.where('LOWER(name) = ?', activity_arg.to_s.strip.downcase).first ||
                TimeEntryActivity.shared.active.where('LOWER(name) = ?', activity_arg.to_s.strip.downcase).first
        end

        if act.nil?
          available = activities.map(&:name).join(', ')
          raise ToolError, "Activity #{activity_arg.inspect} not found. Available activities: #{available}"
        end

        act
      end
    end
  end
end
