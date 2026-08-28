# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class SearchIssues < Tool
      tool 'search_issues',
           title: 'Search issues',
           description: 'Search issues visible to the authenticated user. All filters are optional ' \
                        'and are combined with AND. Returns newest-updated first.',
           permission: :view_issues,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => 'string', 'description' => 'Restrict to one project (identifier or numeric id).' },
               'query' => { 'type' => 'string', 'description' => 'Case-insensitive substring matched against subject and description.' },
               'status' => { 'type' => 'string', 'enum' => %w[open closed all],
                             'description' => 'Issue status filter. Defaults to open.' },
               'tracker' => { 'type' => 'string', 'description' => 'Tracker name, e.g. Bug.' },
               'assigned_to_me' => { 'type' => 'boolean', 'description' => 'Only issues assigned to the authenticated user.' },
               'updated_since' => { 'type' => 'string', 'format' => 'date',
                                    'description' => 'Only issues updated on or after this ISO-8601 date.' },
               'limit' => { 'type' => 'integer', 'minimum' => 1, 'description' => 'Maximum issues to return.' }
             },
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        scope = Issue.visible(user).includes(:project, :tracker, :status, :priority, :author, :assigned_to)

        if (identifier = arguments['project'].presence)
          project = fetch_project(identifier)
          # .visible already filters by role, but not by OAuth scope -- see the
          # note on Tool. This is the check that honours a narrowed token.
          authorize!(:view_issues, project)
          scope = scope.where(project_id: project.id)
        end

        scope =
          case arguments['status'].presence&.to_s
          when 'closed' then scope.joins(:status).where(issue_statuses: { is_closed: true })
          when 'all'    then scope
          else scope.open
          end

        if (needle = arguments['query'].presence)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(needle.to_s)}%"
          scope = scope.where('LOWER(issues.subject) LIKE LOWER(:p) OR LOWER(issues.description) LIKE LOWER(:p)', p: pattern)
        end

        if (tracker_name = arguments['tracker'].presence)
          tracker = Tracker.find_by(name: tracker_name.to_s)
          raise ToolError, "No tracker named #{tracker_name.inspect}" if tracker.nil?

          scope = scope.where(tracker_id: tracker.id)
        end

        scope = scope.where(assigned_to_id: user.id) if arguments['assigned_to_me']

        if (since = arguments['updated_since'].presence)
          begin
            scope = scope.where('issues.updated_on >= ?', Date.iso8601(since.to_s).beginning_of_day)
          rescue ArgumentError
            raise ToolError, "updated_since must be an ISO-8601 date, got #{since.inspect}"
          end
        end

        limit = limit_for(arguments)
        total = scope.count
        {
          total_count: total,
          returned: [total, limit].min,
          issues: scope.reorder(updated_on: :desc).limit(limit).map { |issue| summarise(issue) }
        }
      end

      def summarise(issue)
        {
          id: issue.id,
          subject: issue.subject,
          project: issue.project&.name,
          project_identifier: issue.project&.identifier,
          tracker: issue.tracker&.name,
          status: issue.status&.name,
          priority: issue.priority&.name,
          author: issue.author&.name,
          assigned_to: issue.assigned_to&.name,
          done_ratio: issue.done_ratio,
          created_on: iso(issue.created_on),
          updated_on: iso(issue.updated_on)
        }
      end
    end
  end
end
