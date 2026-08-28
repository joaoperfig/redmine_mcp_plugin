# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListEnumerations < Tool
      tool 'list_enumerations',
           title: 'List trackers, statuses and priorities',
           description: 'List the trackers, issue statuses and priorities configured on this Redmine.',
           permission: nil,
           schema: { 'type' => 'object', 'additionalProperties' => false }

      private

      def perform(_arguments)
        {
          trackers: Tracker.sorted.map { |t| { id: t.id, name: t.name } },
          issue_statuses: IssueStatus.sorted.map { |s| { id: s.id, name: s.name, is_closed: s.is_closed? } },
          priorities: IssuePriority.active.map { |p| { id: p.id, name: p.name, is_default: p.is_default? } }
        }
      end
    end
  end
end
