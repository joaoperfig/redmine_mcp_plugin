# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class CreateTimeEntry < Tool
      include TimeEntryHelpers

      tool 'create_time_entry',
           title: 'Log time',
           description: 'Log spent time for the authenticated user on an issue or a project.',
           permission: :log_time,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'issue_id' => { 'type' => 'integer', 'description' => 'Issue to log time on. Either this or project is required.' },
               'project' => { 'type' => %w[string integer],
                             'description' => 'Project identifier or numeric id, for time not tied to an issue.' },
               'hours' => { 'type' => 'number', 'description' => 'Hours spent, e.g. 1.5.' },
               'spent_on' => { 'type' => 'string', 'format' => 'date',
                               'description' => 'ISO-8601 date the time was spent on. Defaults to today.' },
               'activity' => { 'type' => 'string',
                               'description' => 'Activity name. Defaults to the default activity. See list_enumerations.' },
               'comments' => { 'type' => 'string', 'description' => 'Short description of the work.' }
             },
             'required' => %w[hours],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue, project = target(arguments)
        require_time_tracking!(project)
        authorize!(:log_time, project)

        # Mirrors TimelogController#create: author and user are the caller, never
        # client input. Logging for someone else is a separate permission this
        # tool does not offer.
        time_entry = TimeEntry.new(project: project, issue: issue, author: user, user: user,
                                   spent_on: user.today)
        time_entry.safe_attributes = time_entry_attributes(arguments, project)
        raise ToolError, "Could not log time: #{time_entry.errors.full_messages.join('; ')}" unless time_entry.save

        summarise_time_entry(time_entry)
      end

      def target(arguments)
        if (id = arguments['issue_id'].presence)
          issue = Issue.visible(user).find_by(id: id.to_i)
          raise ToolError, "No visible issue with id #{id.inspect}" if issue.nil?

          [issue, issue.project]
        elsif (identifier = arguments['project'].presence)
          [nil, fetch_project(identifier)]
        else
          raise ToolError, 'Either issue_id or project is required'
        end
      end
    end
  end
end
