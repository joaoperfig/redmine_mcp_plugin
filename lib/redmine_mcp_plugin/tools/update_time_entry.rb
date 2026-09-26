# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class UpdateTimeEntry < Tool
      include TimeEntryHelpers

      tool 'update_time_entry',
           title: 'Update time entry',
           description: "Update one of the authenticated user's own time entries. Only the fields given are changed.",
           permission: :edit_own_time_entries,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'id' => { 'type' => 'integer', 'description' => 'Time entry id.' },
               'hours' => { 'type' => 'number', 'description' => 'Hours spent, e.g. 1.5.' },
               'spent_on' => { 'type' => 'string', 'format' => 'date', 'description' => 'ISO-8601 date the time was spent on.' },
               'activity' => { 'type' => 'string', 'description' => 'Activity name. See list_enumerations.' },
               'comments' => { 'type' => 'string', 'description' => 'Short description of the work.' }
             },
             'required' => %w[id],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        time_entry = fetch_own_time_entry(arguments['id'])
        attributes = time_entry_attributes(arguments, time_entry.project)
        raise ToolError, 'Nothing to update' if attributes.empty?

        time_entry.safe_attributes = attributes
        raise ToolError, "Could not update time entry: #{time_entry.errors.full_messages.join('; ')}" unless time_entry.save

        summarise_time_entry(time_entry)
      end
    end
  end
end
