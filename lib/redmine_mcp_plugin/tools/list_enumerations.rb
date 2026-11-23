# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListEnumerations < Base
      tool_name 'list_enumerations'
      title 'List trackers and priorities'
      description 'List the trackers and issue priorities configured on this Redmine. ' \
                  'Issue statuses have their own tool, list_statuses.'
      input_schema('type' => 'object', 'additionalProperties' => false)

      private

      def perform(_arguments)
        {
          trackers: Tracker.sorted.map { |t| { id: t.id, name: t.name } },
          priorities: IssuePriority.active.map { |p| { id: p.id, name: p.name, is_default: p.is_default? } }
        }
      end
    end
  end
end
