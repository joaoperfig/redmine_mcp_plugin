# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListStatuses < Base
      tool_name 'list_statuses'
      title 'List issue statuses'
      description 'List the issue statuses configured on this Redmine, each flagged with whether it ' \
                  'closes the issue.'
      input_schema('type' => 'object', 'additionalProperties' => false)

      private

      def perform(_arguments)
        { statuses: IssueStatus.sorted.map { |status| { id: status.id, name: status.name, is_closed: status.is_closed? } } }
      end
    end
  end
end
