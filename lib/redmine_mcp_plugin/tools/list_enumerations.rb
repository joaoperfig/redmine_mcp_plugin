# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListEnumerations < Base
      tool_name 'list_enumerations'
      title 'List trackers, priorities and activities'
      description 'List the trackers, shared time entry activities and issue priorities configured on this Redmine. ' \
                  'Issue statuses have their own tool, list_statuses.'
      input_schema('type' => 'object', 'additionalProperties' => false)

      private

      def perform(_arguments)
        {
          trackers: Tracker.sorted.map { |t| { id: t.id, name: t.name } },
          priorities: IssuePriority.active.map { |p| { id: p.id, name: p.name, is_default: p.is_default? } },
          time_entry_activities: TimeEntryActivity.shared.active.sorted.map { |a| { id: a.id, name: a.name, is_default: a.is_default? } }
        }
      end
    end
  end
end
