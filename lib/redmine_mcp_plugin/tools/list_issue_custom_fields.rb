# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListIssueCustomFields < Base
      tool_name 'list_issue_custom_fields'
      title 'List issue custom fields'
      description 'List the custom fields you can set when creating an issue in a project, with their ' \
                  'required flag and allowed values. Pass the result to create_issue as custom_fields.'
      # A read tool must declare a read-tier permission: the HTTP gate builds a
      # read step-up challenge from it, and ScopeChallenge refuses to put a
      # write scope such as add_issues in one. add_issues is checked per project
      # in #perform instead, where a token without it gets a tool error.
      permission :view_issues
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

      # #perform refuses unless the caller may add issues, so offer the tool
      # only where that can succeed: some role grants add_issues, and an OAuth
      # token holds the scope or a new sign-in would request it. In read-only
      # mode sign-in asks for read scopes only, so tokens issued then never
      # see a tool that would always refuse them.
      def self.available_to?(user, oauth_scopes:)
        super &&
          ScopeChallenge.obtainable?(oauth_scopes, %i[add_issues]) &&
          role_allows?(user, oauth_scopes: oauth_scopes, permissions: %i[add_issues])
      end

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
