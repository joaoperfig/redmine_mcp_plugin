# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListTimeEntryActivities < Base
      tool_name 'list_time_entry_activities'
      title 'List time entry activities'
      description 'List the active time entry activities available for logging time, ' \
                  'optionally restricted to one project.'
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id. ' \
                                          'Omit to list shared activities.' }
        },
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project']) if arguments['project'].present?

        if project && !project.module_enabled?(:time_tracking)
          raise ToolError, "The time tracking module is not enabled for project #{project.identifier}"
        end

        default_id = TimeEntryActivity.default_activity_id(user, project)
        activities = TimeEntryActivity.available_activities(project).to_a

        {
          project_identifier: project&.identifier,
          activities: activities.map do |activity|
            {
              id: activity.id,
              name: activity.name,
              is_default: activity.id == default_id,
              project_id: activity.project_id
            }
          end
        }
      end
    end
  end
end
