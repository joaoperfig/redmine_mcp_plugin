# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class LogTime < Base
      tool_name 'log_time'
      title 'Log time'
      description 'Log hours against an existing issue or a project as the authenticated user.'
      permission :log_time
      write true
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id. Use either ' \
                                          'project or issue_id; without issue_id, time is ' \
                                          'logged against the project rather than an issue.' },
          'issue_id' => { 'type' => 'integer',
                          'description' => 'Issue id. Resolves the issue and its project. ' \
                                           'Use either project or issue_id.' },
          'hours' => { 'type' => 'number', 'exclusiveMinimum' => 0,
                       'description' => 'Hours to log, greater than zero.' },
          'activity_id' => { 'type' => %w[integer string],
                             'description' => 'Time entry activity name or numeric id. ' \
                                              'Defaults to the project default activity.' },
          'comments' => { 'type' => 'string', 'description' => 'Comment for the time entry.' },
          'spent_on' => { 'type' => 'string',
                          'description' => 'Date the time was spent, as YYYY-MM-DD. Defaults to today.' },
          'custom_fields' => {
            'type' => 'object',
            'description' => 'Custom field values keyed by field id or name. Use ' \
                             'list_time_entry_fields to discover fields, required flags and ' \
                             'allowed values.',
            'additionalProperties' => {
              'type' => %w[string number boolean array null],
              'items' => { 'type' => %w[string number boolean null] }
            }
          }
        },
        'required' => %w[hours],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project, issue = resolve_context(arguments)
        authorize!(:log_time, project)

        # User and author are set explicitly: TimeEntry otherwise falls back to
        # User.current, which is not guaranteed to be the caller when the tool
        # runs outside a request (tests, jobs).
        entry = TimeEntry.new(
          project: project,
          issue: issue,
          author: user,
          user: user,
          activity_id: resolve_activity(arguments['activity_id'], project),
          hours: arguments['hours'],
          comments: arguments['comments'].presence,
          spent_on: spent_on(arguments)
        )
        apply_custom_fields(entry, arguments['custom_fields'])
        raise ToolError, "Could not log time: #{entry.errors.full_messages.join('; ')}" unless entry.save

        time_entry_payload(entry)
      end

      # An issue carries its project, so a caller can pass only issue_id. Passing
      # both checks that they agree instead of silently logging against one.
      def resolve_context(arguments)
        issue = visible_issue(arguments['issue_id']) if arguments['issue_id'].present?
        project = fetch_project(arguments['project']) if arguments['project'].present?

        if project && issue && issue.project_id != project.id
          raise ToolError, "Issue #{issue.id} is not in project #{project.identifier}"
        end

        project ||= issue&.project
        if project.nil?
          raise ToolError, 'Provide project or issue_id to log time'
        end

        unless project.module_enabled?(:time_tracking)
          raise ToolError, "The time tracking module is not enabled for project #{project.identifier}"
        end

        [project, issue]
      end

      # Issue#visible? applies the token's scopes on top of the role check in
      # Issue.visible, so a token without view_issues cannot log time on an issue
      # it could not read.
      def visible_issue(identifier)
        issue = Issue.visible(user).find_by(id: identifier.to_i)
        raise ToolError, "No visible issue with id #{identifier.inspect}" unless issue&.visible?(user)

        issue
      end

      # Both user and author are set explicitly above: TimeEntry falls back to
      # User.current for author and default activity, which is not guaranteed to
      # be the caller when the tool runs outside a request (tests, jobs).
      def resolve_activity(identifier, project)
        return default_activity_id(project) if identifier.nil? || identifier.to_s.strip.empty?

        activity = find_activity(project, identifier)
        if activity.nil?
          raise ToolError,
                "No active time entry activity matching #{identifier.inspect} on #{project.identifier}"
        end

        activity.id
      end

      # Redmine has no default activity unless an administrator marks one, so
      # a nil default usually means "choose one", not "none exist".
      def default_activity_id(project)
        id = TimeEntryActivity.default_activity_id(user, project)
        return id if id

        names = project.activities.map(&:name)
        raise ToolError, "No active time entry activities are available for #{project.identifier}" if names.empty?

        raise ToolError, "#{project.identifier} has no default time entry activity, so pass activity_id " \
                         "(name or id). Available: #{names.join(', ')}. See list_time_entry_activities."
      end

      # The activity must be one of the project's available activities, which
      # already excludes inactive and overridden parent activities. TimeEntry
      # would reject the value later, but resolving here gives the caller an
      # actionable message instead of a generic validation failure.
      def find_activity(project, identifier)
        activities = project.activities.to_a
        if identifier.is_a?(Integer) || identifier.to_s.match?(/\A\d+\z/)
          activities.find { |activity| activity.id == identifier.to_i }
        else
          activities.find { |activity| activity.name.to_s.casecmp?(identifier.to_s) }
        end
      end

      def spent_on(arguments)
        raw = arguments['spent_on'].presence
        return user.today if raw.nil?

        Date.iso8601(raw.to_s)
      rescue ArgumentError
        raise ToolError, 'spent_on must be a date in YYYY-MM-DD format'
      end

      # Only fields the caller can actually edit are accepted. Without this
      # check, acts_as_customizable would silently ignore an id that is hidden
      # or belongs to another customizable type, and the caller would believe
      # the value was saved.
      def apply_custom_fields(entry, raw)
        return if raw.blank?

        unless raw.is_a?(Hash)
          raise ToolError, 'custom_fields must be an object keyed by field id or name'
        end

        fields = entry.editable_custom_fields(user)
        by_id = fields.index_by { |field| field.id.to_s }
        by_name = fields.index_by { |field| field.name.to_s }

        values = raw.to_h do |key, value|
          field = by_id[key.to_s] || by_name[key.to_s] ||
                  fields.find { |candidate| candidate.name.to_s.casecmp?(key.to_s) }
          if field.nil?
            raise ToolError,
                  "Unknown or non-editable time entry custom field #{key.inspect}. " \
                  'Use list_time_entry_fields to discover the available fields.'
          end

          [field.id.to_s, normalize_custom_field_value(field, value)]
        end

        entry.custom_field_values = values
      end

      def normalize_custom_field_value(field, value)
        if field.multiple?
          values = value.is_a?(Array) ? value : [value]
          values.map { |item| normalize_custom_field_scalar(field, item) }
        elsif value.is_a?(Array)
          raise ToolError, "Custom field #{field.name.inspect} accepts a single value"
        else
          normalize_custom_field_scalar(field, value)
        end
      end

      # Redmine's boolean custom fields store "1"/"0", while JSON callers are
      # likely to send true/false. Convert those here so the value actually
      # round-trips instead of being cast to false by BoolFormat.
      def normalize_custom_field_scalar(field, value)
        return nil if value.nil?

        if field.field_format == 'bool'
          normalized = value.to_s.strip.downcase
          return '1' if value == true || %w[1 true yes on].include?(normalized)
          return '0' if value == false || %w[0 false no off].include?(normalized)
          return '' if normalized.empty?

          raise ToolError, "Custom field #{field.name.inspect} expects a boolean value"
        else
          value.to_s
        end
      end

      def time_entry_payload(entry)
        {
          id: entry.id,
          issue_id: entry.issue_id,
          project_identifier: entry.project&.identifier,
          user: identity(entry.user),
          hours: entry.hours.to_f,
          activity: { id: entry.activity_id, name: entry.activity&.name },
          comments: entry.comments.presence,
          spent_on: entry.spent_on&.iso8601,
          created_on: iso(entry.created_on),
          custom_fields: custom_field_payload(entry)
        }
      end

      def custom_field_payload(entry)
        entry.visible_custom_field_values(user).map do |value|
          {
            id: value.custom_field_id,
            name: value.custom_field.name,
            value: value.value
          }
        end
      end
    end
  end
end
