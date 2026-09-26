# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class DeleteTimeEntry < Tool
      include TimeEntryHelpers

      tool 'delete_time_entry',
           title: 'Delete time entry',
           description: "Delete one of the authenticated user's own time entries.",
           permission: :edit_own_time_entries,
           write: true,
           destructive: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'id' => { 'type' => 'integer', 'description' => 'Time entry id.' }
             },
             'required' => %w[id],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        time_entry = fetch_own_time_entry(arguments['id'])
        # The summary is taken before destroy, while the associations still load.
        summary = summarise_time_entry(time_entry)
        raise ToolError, 'Could not delete time entry' unless time_entry.destroy

        { deleted: true, time_entry: summary }
      end
    end
  end
end
