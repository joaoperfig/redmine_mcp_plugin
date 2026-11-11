# frozen_string_literal: true

module RedmineMcp
  # Describes and resolves the custom fields a user may set on a new issue.
  #
  # Everything is derived from an unsaved Issue so the answer matches what the
  # Redmine issue form offers: tracker and project assignment, role-based field
  # visibility and workflow read-only/required rules.
  module IssueCustomFields
    class << self
      # Returns the tracker named +name+ of +project+, or its first tracker when
      # no name is given.
      def tracker_for(project, name)
        if name.present?
          project.trackers.find_by(name: name.to_s) ||
            raise(ToolError, "Project #{project.identifier} has no tracker named #{name.to_s.inspect}")
        else
          project.trackers.first ||
            raise(ToolError, "Project #{project.identifier} has no trackers")
        end
      end

      # The initial status matters: workflow required/read-only rules are looked
      # up by tracker and status.
      def new_issue(project, tracker, user)
        issue = Issue.new(project: project, tracker: tracker, author: user)
        issue.status = tracker.default_status
        issue
      end

      # Issue#editable_custom_field_values drops fields hidden from the user's
      # roles and fields the workflow makes read-only. Reading custom_field_values
      # directly would expose fields core keeps from this user.
      def describe(issue, user)
        issue.editable_custom_field_values(user).map do |value|
          field = value.custom_field
          {
            id: field.id,
            name: field.name,
            field_format: field.field_format,
            required: field.is_required? || issue.required_attribute?(field.id.to_s, user),
            multiple: field.multiple?,
            default_value: field.default_value,
            possible_values: possible_values(field, issue)
          }
        end
      end

      # Turns the tool's +entries+ ({'id' or 'name', 'value'}) into the
      # {custom_field_id => stored value} hash Issue#custom_field_values= takes.
      # The issue must already carry its tracker: the settable fields depend on it.
      #
      # An entry naming a field the user cannot set raises the same error whether
      # the field does not exist, is not on this tracker, or is hidden from the
      # user's roles, so the message cannot confirm hidden fields.
      def resolve(issue, user, entries)
        settable = issue.editable_custom_field_values(user).map(&:custom_field)

        entries.each_with_object({}) do |entry, resolved|
          field = find_field(issue, settable, entry)
          raise ToolError, "Custom field #{field.name.inspect} is given more than once" if resolved.key?(field.id.to_s)

          resolved[field.id.to_s] = stored_value(field, entry['value'], issue)
        end
      end

      private

      def find_field(issue, settable, entry)
        id = entry['id']
        name = entry['name'].presence
        raise ToolError, 'Each custom field entry needs exactly one of id or name' if id.nil? == name.nil?

        field = id.nil? ? settable.find { |f| f.name == name.to_s } : settable.find { |f| f.id == id.to_i }
        return field if field

        raise ToolError,
              "No custom field #{(id || name).inspect} can be set on #{issue.tracker.name} issues in " \
              "#{issue.project.identifier}; see list_issue_custom_fields"
      end

      def stored_value(field, value, issue)
        if value.is_a?(Array) && !field.multiple?
          raise ToolError, "Custom field #{field.name.inspect} takes a single value"
        end

        values = Array(value).map { |v| stored_option(field, v.to_s, issue) }
        field.multiple? ? values : values.first
      end

      # Callers send the label they read from list_issue_custom_fields. Core
      # stores the option value (an id for enumeration, user and version fields),
      # so a label that matches exactly one option is translated. Anything else
      # passes through for core's own validation to accept or reject.
      def stored_option(field, value, issue)
        options = field.possible_values_options(issue)
        return value if options.none?(Array) || options.any? { |_label, stored| stored.to_s == value }

        matches = options.select { |label, _stored| label.to_s == value }
        matches.one? ? matches.first.last.to_s : value
      end

      # Core returns plain strings or [label, value] pairs depending on the
      # format. Callers always get {value, label}; nil means free text.
      def possible_values(field, issue)
        options = field.possible_values_options(issue)
        return nil if options.empty?

        options.map do |option|
          label, value = Array(option)
          { value: (value || label).to_s, label: label.to_s }
        end
      end
    end
  end
end
