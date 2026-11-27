# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListTimeEntryFields < Base
      tool_name 'list_time_entry_fields'
      title 'List time entry fields'
      description 'List the required and custom fields for logging time on an issue or project. ' \
                  'Pass the returned custom field ids or names to log_time custom_fields.'
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id. ' \
                                          'Use either project or issue_id.' },
          'issue_id' => { 'type' => 'integer',
                          'description' => 'Issue id. Resolves the project and issue context. ' \
                                           'Use either project or issue_id.' }
        },
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project, issue = resolve_context(arguments)
        if project && !project.module_enabled?(:time_tracking)
          raise ToolError, "The time tracking module is not enabled for project #{project.identifier}"
        end

        entry = TimeEntry.new(project: project, issue: issue, author: user, user: user,
                              spent_on: user.today)
        fields = entry.editable_custom_fields(user)

        {
          project_identifier: project.identifier,
          issue_id: issue&.id,
          required_fields: required_fields(issue),
          custom_fields: fields.map { |field| field_payload(field, entry) },
          required_custom_fields: fields.select(&:is_required?).map { |field| field_ref(field) }
        }
      end

      def resolve_context(arguments)
        issue = visible_issue(arguments['issue_id']) if arguments['issue_id'].present?
        project = fetch_project(arguments['project']) if arguments['project'].present?

        if project && issue && issue.project_id != project.id
          raise ToolError, "Issue #{issue.id} is not in project #{project.identifier}"
        end

        project ||= issue&.project
        if project.nil?
          raise ToolError, 'Provide project or issue_id to discover the time entry fields'
        end

        [project, issue]
      end

      # Issue#visible? applies the token's scopes on top of the role check in
      # Issue.visible, so a token without view_issues cannot use this to learn
      # which project an issue belongs to.
      def visible_issue(identifier)
        issue = Issue.visible(user).find_by(id: identifier.to_i)
        raise ToolError, "No visible issue with id #{identifier.inspect}" unless issue&.visible?(user)

        issue
      end

      # These are the arguments log_time requires from the caller: its own
      # required fields plus Redmine's configurable required time-log fields.
      # issue_id is required only in an issue context, or when Redmine itself
      # makes it mandatory for every time entry. spent_on and activity_id are
      # omitted because the tool supplies defaults.
      def required_fields(issue)
        configured = Array(Setting.timelog_required_fields).map(&:to_s)
        fields = %w[hours]
        fields << 'issue_id' if issue || configured.include?('issue_id')
        (fields + configured).uniq
      end

      def field_payload(field, entry)
        {
          id: field.id,
          name: field.name,
          description: field.description.presence,
          field_format: field.field_format,
          is_required: field.is_required?,
          multiple: field.multiple?,
          default_value: field_default_value(field),
          regexp: field.regexp.presence,
          min_length: field.min_length,
          max_length: field.max_length,
          possible_values: possible_values(field, entry)
        }
      end

      # CustomField#default_value resolves date offsets through User.current,
      # which is not guaranteed to be the caller when a tool runs outside a
      # request. Mirror that calculation with the authenticated user instead.
      def field_default_value(field)
        raw = field[:default_value]
        return nil if raw.blank?

        if field.field_format == 'date' && field.default_value_mode == 'date_offset'
          (user.today + Integer(raw, 10)).iso8601
        else
          raw
        end
      rescue ArgumentError
        raw
      end

      def field_ref(field)
        { id: field.id, name: field.name, field_format: field.field_format }
      end

      # Redmine's field formats return either [label, value] pairs or plain
      # values. Normalize both shapes so an agent can pass the value back
      # without having to know which format the field uses.
      def possible_values(field, entry)
        field.possible_values_options(entry).map do |option|
          if option.is_a?(Array)
            { label: option[0].to_s, value: option[1].to_s }
          else
            { label: option.to_s, value: option.to_s }
          end
        end
      end
    end
  end
end
