# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListEnumerations < Tool
      tool 'list_enumerations',
           title: 'List trackers, statuses, priorities and activities',
           description: 'List the trackers, issue statuses, priorities and shared time entry activities ' \
                        'configured on this Redmine.',
           permission: nil,
           schema: { 'type' => 'object', 'additionalProperties' => false }

      private

      def perform(_arguments)
        {
          trackers: Tracker.sorted.map { |t| { id: t.id, name: t.name } },
          issue_statuses: IssueStatus.sorted.map { |s| { id: s.id, name: s.name, is_closed: s.is_closed? } },
          priorities: IssuePriority.active.map { |p| { id: p.id, name: p.name, is_default: p.is_default? } },
          # Shared activities only; a project can disable or override them.
          time_entry_activities: TimeEntryActivity.shared.active.sorted
                                                  .map { |a| { id: a.id, name: a.name, is_default: a.is_default? } }
        }
      end
    end
  end
end
