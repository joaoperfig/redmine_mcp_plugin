# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListIssueCustomFields < Base
      tool_name 'list_issue_custom_fields'
      title 'List issue custom fields'
      description 'List the custom fields you can set when creating an issue in a project, with their ' \
                  'required flag and allowed values. Pass the result to create_issue as custom_fields.'
      permission :add_issues
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id.' },
          'tracker' => { 'type' => 'string',
                         'description' => 'Tracker name. Defaults to the first tracker of the project.' }
        },
        'required' => %w[project],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        authorize!(:add_issues, project)

        tracker = IssueCustomFields.tracker_for(project, arguments['tracker'])
        issue = IssueCustomFields.new_issue(project, tracker, user)

        { project_identifier: project.identifier, tracker: tracker.name,
          custom_fields: IssueCustomFields.describe(issue, user) }
      end
    end
  end
end
