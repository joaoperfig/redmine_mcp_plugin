# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListTimeEntries < Tool
      include TimeEntryHelpers

      tool 'list_time_entries',
           title: 'List time entries',
           description: 'List spent time visible to the authenticated user. All filters are optional ' \
                        'and are combined with AND. Returns the latest spent_on first.',
           permission: :view_time_entries,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => %w[string integer],
                             'description' => 'Restrict to one project (identifier or numeric id).' },
               'issue_id' => { 'type' => 'integer', 'description' => 'Restrict to one issue.' },
               'user' => { 'type' => 'string', 'description' => 'Login of the user who spent the time, or "me".' },
               'from' => { 'type' => 'string', 'format' => 'date', 'description' => 'Earliest spent_on, inclusive.' },
               'to' => { 'type' => 'string', 'format' => 'date', 'description' => 'Latest spent_on, inclusive.' },
               'offset' => { 'type' => 'integer', 'minimum' => 0,
                             'description' => 'Rows to skip, for paging past the server cap. Defaults to 0.' },
               'limit' => { 'type' => 'integer', 'minimum' => 1, 'description' => 'Maximum entries to return.' }
             },
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        scope = TimeEntry.visible(user).includes(:project, :issue, :user, :activity)

        if (identifier = arguments['project'].presence)
          project = fetch_project(identifier)
          # .visible filters by role, not by OAuth scope -- see the note on Tool.
          authorize!(:view_time_entries, project)
          scope = scope.where(project_id: project.id)
        end

        # No issue lookup: a refusal for an unknown issue would confirm issue
        # existence to a token scoped without view_issues.
        scope = scope.where(issue_id: arguments['issue_id'].to_i) if arguments['issue_id'].present?

        if (login = arguments['user'].presence)
          # A subquery rather than a lookup: an unknown login and an invisible
          # one both give an empty list, so the filter does not confirm accounts.
          scope = scope.where(user_id: login.to_s == 'me' ? user.id : User.where(login: login.to_s).select(:id))
        end

        scope = scope.where('time_entries.spent_on >= ?', parse_date(arguments, 'from')) if arguments['from'].present?
        scope = scope.where('time_entries.spent_on <= ?', parse_date(arguments, 'to')) if arguments['to'].present?

        limit  = limit_for(arguments)
        offset = offset_for(arguments)
        rows   = scope.reorder(spent_on: :desc, id: :desc).offset(offset).limit(limit)
                      .map { |time_entry| summarise_time_entry(time_entry) }
        paged(total: scope.count, offset: offset, key: :time_entries, rows: rows)
          .merge(total_hours: scope.sum(:hours).to_f.round(2))
      end

      def parse_date(arguments, key)
        Date.iso8601(arguments[key].to_s)
      rescue ArgumentError
        raise ToolError, "#{key} must be an ISO-8601 date, got #{arguments[key].inspect}"
      end
    end
  end
end
