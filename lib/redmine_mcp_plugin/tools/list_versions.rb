# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListVersions < Base
      tool_name 'list_versions'
      title 'List versions'
      description 'List the versions (milestones) available in a project, optionally with time totals.'
      permission :view_issues
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id.' },
          'include_time_totals' => { 'type' => 'boolean',
                                     'description' => 'Include estimated and spent hours. Requires ' \
                                                      'view_time_entries. Defaults to false.' },
          'offset' => { 'type' => 'integer', 'minimum' => 0,
                        'description' => 'Rows to skip, for paging past the server cap. Defaults to 0.' },
          'limit' => { 'type' => 'integer', 'minimum' => 1 }
        },
        'required' => %w[project],
        'additionalProperties' => false
      )

      # Time totals add their own permission so the HTTP gate can challenge for
      # the whole operation before the body runs.
      def self.required_permissions(arguments = {})
        permissions = super
        arguments['include_time_totals'] == true ? permissions + %i[view_time_entries] : permissions
      end

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        # .visible filters by role but not by a narrowed OAuth scope.
        authorize!(:view_issues, project)

        include_totals = arguments['include_time_totals'] == true
        authorize!(:view_time_entries, project) if include_totals

        # shared_versions matches what issues in this project can target,
        # including versions shared from parent projects.
        versions = project.shared_versions.sort
        limit    = limit_for(arguments)
        offset   = offset_for(arguments)
        rows     = (versions.slice(offset, limit) || []).map { |version| summarise(version, include_totals) }
        paged(total: versions.size, offset: offset, key: :versions, rows: rows)
      end

      def summarise(version, include_totals)
        data = {
          id: version.id,
          name: version.name,
          description: version.description.presence,
          status: version.status,
          due_date: version.due_date&.iso8601,
          sharing: version.sharing,
          wiki_page_title: version.wiki_page_title.presence,
          project_id: version.project_id,
          created_on: iso(version.created_on),
          updated_on: iso(version.updated_on)
        }
        if include_totals
          data[:estimated_hours] = version.estimated_hours
          data[:spent_hours] = version.spent_hours
        end
        data
      end
    end
  end
end
