# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class GetIssue < Tool
      tool 'get_issue',
           title: 'Get issue',
           description: 'Fetch one issue by id, with its description and optionally its notes and history.',
           permission: :view_issues,
           schema: {
             'type' => 'object',
             'properties' => {
               'id' => { 'type' => 'integer', 'description' => 'Issue id.' },
               'include_journals' => { 'type' => 'boolean',
                                       'description' => 'Include notes and change history. Defaults to true.' }
             },
             'required' => %w[id],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue = Issue.visible(user).find_by(id: arguments['id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['id'].inspect}" if issue.nil?

        authorize!(:view_issues, issue.project)

        payload = {
          id: issue.id,
          subject: issue.subject,
          description: issue.description,
          project: issue.project&.name,
          project_identifier: issue.project&.identifier,
          tracker: issue.tracker&.name,
          status: issue.status&.name,
          priority: issue.priority&.name,
          author: issue.author&.name,
          assigned_to: issue.assigned_to&.name,
          category: issue.category&.name,
          fixed_version: issue.fixed_version&.name,
          parent_id: issue.parent_id,
          start_date: issue.start_date&.iso8601,
          due_date: issue.due_date&.iso8601,
          done_ratio: issue.done_ratio,
          estimated_hours: issue.estimated_hours,
          is_private: issue.is_private?,
          created_on: iso(issue.created_on),
          updated_on: iso(issue.updated_on),
          custom_fields: visible_custom_fields(issue)
        }

        include_journals = arguments.fetch('include_journals', true)
        payload[:journals] = journals_for(issue) if include_journals
        payload
      end

      # Issue#visible_custom_field_values applies per-field role visibility.
      # Reading custom_field_values directly would leak fields core hides.
      def visible_custom_fields(issue)
        issue.visible_custom_field_values.map do |value|
          { id: value.custom_field_id, name: value.custom_field.name, value: value.value }
        end
      end

      # Journal#notes can be private (private_notes), and core gates that on
      # :view_private_notes. Journal.visible applies exactly that rule.
      def journals_for(issue)
        issue.journals.visible(user).includes(:user).order(:created_on).map do |journal|
          {
            id: journal.id,
            user: journal.user&.name,
            notes: journal.notes.presence,
            private_notes: journal.private_notes?,
            created_on: iso(journal.created_on),
            details: journal.visible_details(user).map do |detail|
              { property: detail.property, name: detail.prop_key,
                old_value: detail.old_value, new_value: detail.value }
            end
          }
        end
      end
    end
  end
end
