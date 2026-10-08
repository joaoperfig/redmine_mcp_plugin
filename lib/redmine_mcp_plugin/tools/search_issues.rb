# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class SearchIssues < Tool
      FILTER_ALIASES = {
        'assigned_to' => 'assigned_to_id',
        'author' => 'author_id',
        'category' => 'category_id',
        'fixed_version' => 'fixed_version_id',
        'priority' => 'priority_id',
        'status' => 'status_id',
        'tracker' => 'tracker_id',
        'watcher' => 'watcher_id',
      }.freeze

      NAMED_FILTERS = (FILTER_ALIASES.keys + %w[last_updated_by updated_by]).freeze
      USER_NAMED_FILTERS = %w[assigned_to author last_updated_by updated_by watcher].freeze

      OPERATOR_GROUPS_DESCRIPTION =
        'Operator groups: ' \
        'List: "=" is one of, "!" is not one of. History List additionally supports "ev" (has been), "!ev" ' \
        '(has never been), and "cf" (changed from). Nullable History List additionally supports "*" (any) and "!*" ' \
        '(none); omit values for "*" and "!*". ' \
        'Text: "~" contains, "*~" contains any, "!~" does not contain, "^" starts with, "$" ends with, "*" is not ' \
        'empty, "!*" is empty; omit values for "*" and "!*". ' \
        'Date: "=" on date, ">=" on or after, "<=" on or before, "><" between, "*" is not empty, "!*" is empty; ' \
        '"><" expects two values and "*" / "!*" take no values; use ISO dates such as "2026-10-01". ' \
        'Numeric: "=" equals, ">=" at least, "<=" at most, "><" between, "*" is not empty, "!*" is empty; ' \
        '"><" expects two values and "*" / "!*" take no values. ' \
        'Status: "o" any open, "=" is one of, "!" is not one of, "ev" has been, "!ev" has never been, "cf" changed ' \
        'from, "c" any closed, "*" any status; omit values for "o", "c" and "*". ' \
        'Native Redmine relative-date operators are also accepted, but absolute ISO dates are recommended for ' \
        'MCP calls.'

      def self.issue_filter_schema(
        description,
        values_description = 'Array of filter values. Omit for operators that take no value.'
      )
        {
          'type' => 'object',
          'description' => description,
          'properties' => {
            'operator' => { 'type' => 'string' },
            'values' => {
              'type' => 'array',
              'items' => { 'type' => %w[string integer number boolean] },
              'description' => values_description,
            },
          },
          'required' => %w[operator],
          'additionalProperties' => false,
        }
      end
      private_class_method :issue_filter_schema

      tool 'search_issues',
           title: 'Search issues',
           description: 'Search issues visible to the authenticated user. By default issues of all statuses are ' \
                        'searched. Use query for subject/description text search and filters for Redmine issue-list ' \
                        'filters; all conditions are combined with AND. Returns newest-updated first.',
           permission: :view_issues,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => {
                 'type' => %w[string integer],
                 'description' => 'Optional project context (identifier or numeric id). Restricts results to that ' \
                                  'project by default and makes project-specific Redmine filters available.'
               },
               'query' => {
                 'type' => 'string',
                 'description' => 'Case-insensitive substring matched against issue subject and description.'
               },
               'filters' => {
                 'type' => 'object',
                 'description' =>
                   'Redmine issue-list filters. Recommended human-readable filters are documented explicitly below ' \
                   'and resolve their values using the choices Redmine exposes for the current query. ' \
                   'Some listed filters may be unavailable in a particular project because Redmine disables fields ' \
                   'based on project/tracker configuration or permissions. User filters accept display names, ' \
                   'logins, and the special value "me"; use a login to disambiguate duplicate display names. ' \
                   'Additional native Redmine filters are accepted as additional properties, including *_id fields ' \
                   'for callers that already know exact IDs, plugin/relation/project-specific filters, and cf_<id> ' \
                   'custom fields. ' + OPERATOR_GROUPS_DESCRIPTION,
                 'properties' => {
                   'assigned_to' => issue_filter_schema(
                     'Filter by assignee. Uses Nullable History List operators. Depending on configuration, ' \
                     'assignees may include groups.',
                     'Array of user display names, logins or "me".'
                   ),
                   'author' => issue_filter_schema(
                     'Filter by issue author/creator. Uses List operators.',
                     'Array of user display names, logins or "me".'
                   ),
                   'category' => issue_filter_schema(
                     'Filter by issue category name. Uses Nullable History List operators. Available only in a ' \
                     'project context.',
                     'Category names.'
                   ),
                   'closed_on' => issue_filter_schema(
                     'Issue closed date. Uses Date operators. Prefer absolute ISO dates such as "2026-10-01".',
                     'ISO date values.'
                   ),
                   'created_on' => issue_filter_schema(
                     'Issue creation date. Uses Date operators. Prefer absolute ISO dates such as "2026-10-01".',
                     'ISO date values.'
                   ),
                   'description' => issue_filter_schema(
                     'Issue description text filter. Uses Text operators.',
                     'Text values.'
                   ),
                   'done_ratio' => issue_filter_schema(
                     'Issue completion percentage. Uses Numeric operators.',
                     'Numeric percentage values.'
                   ),
                   'due_date' => issue_filter_schema(
                     'Issue due date. Uses Date operators. Prefer absolute ISO dates such as "2026-10-01".',
                     'ISO date values.'
                   ),
                   'fixed_version' => issue_filter_schema(
                     'Filter by target-version label, typically "Project - Version". Uses ' \
                     'Nullable History List operators. Ambiguous labels are rejected; use the native ' \
                     'fixed_version_id filter to disambiguate.',
                     'Target-version labels.'
                   ),
                   'issue_id' => issue_filter_schema(
                     'Issue numeric ID. Uses Numeric operators.',
                     'Numeric issue IDs.'
                   ),
                   'last_updated_by' => issue_filter_schema(
                     'Filter by the user who performed the latest visible update. Uses List operators.',
                     'Array of user display names, logins or "me".'
                   ),
                   'notes' => issue_filter_schema(
                     'Issue notes/comments text filter. Uses Text operators.',
                     'Text values.'
                   ),
                   'priority' => issue_filter_schema(
                     'Filter by priority name. Uses History List operators.',
                     'Priority names, e.g. "High".'
                   ),
                   'start_date' => issue_filter_schema(
                     'Issue start date. Uses Date operators. Prefer absolute ISO dates such as "2026-10-01".',
                     'ISO date values.'
                   ),
                   'status' => issue_filter_schema(
                     'Filter by issue status name. Uses Status operators. If omitted, issues of all statuses are ' \
                     'searched.',
                     'Status names, e.g. "New" or "Resolved".'
                   ),
                   'subject' => issue_filter_schema(
                     'Issue subject text filter. Uses Text operators.',
                     'Text values.'
                   ),
                   'tracker' => issue_filter_schema(
                     'Filter by tracker name. Uses History List operators.',
                     'Tracker names, e.g. "Bug".'
                   ),
                   'updated_by' => issue_filter_schema(
                     'Filter by a user who has updated the issue. Uses List operators.',
                     'Array of user display names, logins or "me".'
                   ),
                   'updated_on' => issue_filter_schema(
                     'Issue last-updated date. Uses Date operators. Prefer absolute ISO dates such as "2026-10-01".',
                     'ISO date values.'
                   ),
                   'watcher' => issue_filter_schema(
                     'Filter by a user who watches the issue. Uses List operators.',
                     'Array of user display names, logins or "me".'
                   ),
                 },
                 'additionalProperties' => issue_filter_schema(
                   'Additional native Redmine IssueQuery filter. Valid operators and values depend on the filter ' \
                   'type, current project, and Redmine configuration.'
                 )
               },
               'offset' => {
                 'type' => 'integer',
                 'minimum' => 0,
                 'description' => 'Rows to skip, for paging past the server cap. Defaults to 0.'
               },
               'limit' => {
                 'type' => 'integer',
                 'minimum' => 1,
                 'description' => 'Maximum issues to return.'
               }
             },
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue_query = build_issue_query(arguments)
        scope = issue_query.base_scope

        if (needle = arguments['query'].presence)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(needle.to_s)}%"
          scope = scope.where(
            'LOWER(issues.subject) LIKE LOWER(:p) OR LOWER(issues.description) LIKE LOWER(:p)',
            p: pattern
          )
        end

        limit  = limit_for(arguments)
        offset = offset_for(arguments)
        total  = scope.count
        rows   = scope.preload(:project, :tracker, :status, :priority, :author, :assigned_to)
                      .reorder(updated_on: :desc)
                      .offset(offset)
                      .limit(limit)
                      .map { |issue| summarise(issue) }
        paged(total: total, offset: offset, key: :issues, rows: rows)
      end

      def build_issue_query(arguments)
        project = nil
        if (identifier = arguments['project'].presence)
          project = fetch_project(identifier)
          # .visible already filters by role, but not by OAuth scope -- see the
          # note on Tool. This is the check that honours a narrowed token.
          authorize!(:view_issues, project)
        end

        issue_query = IssueQuery.new(name: '_', project: project)
        # IssueQuery defaults to open issues. MCP search defaults to all statuses; an explicit
        # status/status_id filter below overwrites this native status filter.
        issue_query.add_filter('status_id', '*')

        apply_filters(issue_query, arguments['filters'])

        # A project-scoped IssueQuery can include subprojects depending on the
        # Redmine setting. Keep `project` exact by default unless the caller
        # explicitly supplied a subproject_id filter.
        if project && issue_query.available_filters.key?('subproject_id') && !issue_query.has_filter?('subproject_id')
          issue_query.add_filter('subproject_id', '!*')
        end

        unless issue_query.valid?
          raise ToolError, "Invalid issue filters: #{issue_query.errors.full_messages.join('; ')}"
        end

        issue_query
      end

      def apply_filters(issue_query, filters)
        return if filters.nil?

        normalized_fields = {}
        filters.each do |requested_field, options|
          requested_field = requested_field.to_s
          field = FILTER_ALIASES.fetch(requested_field, requested_field)
          operator = options['operator'].to_s

          if (previous = normalized_fields[field])
            raise ToolError,
                  "Issue filters #{previous.inspect} and #{requested_field.inspect} both refer to #{field.inspect}; use only one"
          end
          normalized_fields[field] = requested_field

          filter = issue_query.available_filters[field]
          unless filter
            available = issue_query.available_filters.keys.join(', ')
            raise ToolError,
                  "Unknown or unavailable issue filter #{requested_field.inspect}. Available Redmine fields: #{available}"
          end

          allowed = Array(issue_query.class.operators_by_filter_type[filter[:type]])
          unless allowed.include?(operator)
            raise ToolError,
                  "Operator #{operator.inspect} is not valid for #{requested_field.inspect}; allowed: " \
                  "#{allowed.join(', ')}"
          end

          values = options['values']&.map(&:to_s)
          if NAMED_FILTERS.include?(requested_field) && values&.any?(&:present?)
            values = resolve_named_filter_values(requested_field, filter, values)
          end

          issue_query.add_filter(field, operator, values)
        end
      end

      # Resolves values supplied for a named MCP filter to native Redmine filter values (typically IDs).
      #
      # @param requested_field [String] MCP filter name, for example "author" or "tracker"
      # @param filter [QueryFilter] Redmine filter definition containing the available [label, value] choices
      # @param values [Array<String>] caller-supplied display names, logins, or other named values
      # @return [Array<String>] native Redmine values suitable for IssueQuery#add_filter
      def resolve_named_filter_values(requested_field, filter, values)
        filter_pairs = Array(filter.values).filter_map do |label, value|
          [label.to_s, value.to_s] unless label.nil? || value.nil?
        end

        if USER_NAMED_FILTERS.include?(requested_field)
          login_pairs = user_login_pairs(filter_pairs)
          values.map do |requested_value|
            resolve_user_filter_value(requested_value, requested_field, filter_pairs, login_pairs)
          end
        else
          values.map do |requested_value|
            resolve_named_filter_value(requested_value, requested_field, filter_pairs)
          end
        end
      end

      def resolve_user_filter_value(requested_value, requested_field, filter_pairs, login_pairs)
        needle = requested_value.strip

        # Redmine exposes "me" as an internal value with a localized display label such as << me >>.
        return 'me' if needle.casecmp?('me') && filter_pairs.any? { |_label, value| value == 'me' }

        # Prefer login over display name so a login can disambiguate duplicate display names.
        login_value = login_pairs.find { |login, _value| login.casecmp?(needle) }&.last
        return login_value if login_value

        matched_values = filter_pairs
          .filter_map { |label, value| value if label.casecmp?(needle) }
          .uniq

        case matched_values.length
        when 1
          matched_values.first
        when 0
          raise ToolError,
                "Unknown value #{requested_value.inspect} for issue filter #{requested_field.inspect}; " \
                'use a user display name, login, or "me"'
        else
          raise ToolError,
                "Ambiguous value #{requested_value.inspect} for issue filter #{requested_field.inspect}; " \
                'use the user login to disambiguate'
        end
      end

      def resolve_named_filter_value(requested_value, requested_field, filter_pairs)
        needle = requested_value.strip
        native_field = FILTER_ALIASES.fetch(requested_field, requested_field)

        matched_values = filter_pairs
          .filter_map { |label, value| value if label.casecmp?(needle) }
          .uniq

        case matched_values.length
        when 1
          matched_values.first
        when 0
          raise ToolError,
                "Unknown value #{requested_value.inspect} for issue filter #{requested_field.inspect}; " \
                "use a display value available in Redmine or the native #{native_field.inspect} filter"
        else
          raise ToolError,
                "Ambiguous value #{requested_value.inspect} for issue filter #{requested_field.inspect}; " \
                "matching Redmine values: #{matched_values.join(', ')}. Use the native #{native_field.inspect} " \
                'filter to disambiguate'
        end
      end

      # Builds login-to-native-value pairs for user choices already exposed by Redmine for this
      # filter. Restricting the lookup to those values preserves Redmine's
      # project/permission-specific user visibility instead of resolving arbitrary users globally by
      # login. Non-numeric values such as "me" are ignored here.
      #
      # @param filter_pairs [Array<Array(String, String)>] Redmine [display label, native value] choices
      # @return [Array<Array(String, String)>] [user login, native filter value] pairs
      def user_login_pairs(filter_pairs)
        user_ids = filter_pairs.filter_map do |_label, value|
          Integer(value, exception: false)
        end
        logins_by_id = User.where(id: user_ids).pluck(:id, :login).to_h

        filter_pairs.filter_map do |_label, value|
          login = logins_by_id[value.to_i]
          [login.to_s, value] if login.present?
        end
      end

      def summarise(issue)
        {
          id: issue.id,
          subject: issue.subject,
          project: issue.project&.name,
          project_identifier: issue.project&.identifier,
          tracker: issue.tracker&.name,
          status: issue.status&.name,
          priority: issue.priority&.name,
          author: issue.author&.name,
          assigned_to: issue.assigned_to&.name,
          parent_id: issue.parent_id,
          done_ratio: issue.done_ratio,
          start_date: issue.start_date&.iso8601,
          due_date: issue.due_date&.iso8601,
          created_on: iso(issue.created_on),
          updated_on: iso(issue.updated_on),
          closed_on: iso(issue.closed_on),
        }
      end
    end
  end
end
