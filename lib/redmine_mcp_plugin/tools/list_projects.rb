# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListProjects < Tool
      tool 'list_projects',
           title: 'List projects',
           description: 'List the Redmine projects visible to the authenticated user.',
           permission: :view_project,
           schema: {
             'type' => 'object',
             'properties' => {
               'name' => { 'type' => 'string',
                           'description' => 'Optional case-insensitive substring to filter project name or identifier by.' },
               'limit' => { 'type' => 'integer', 'description' => 'Maximum projects to return.', 'minimum' => 1 }
             },
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        scope = Project.visible(user).order(:lft)
        if (needle = arguments['name'].presence)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(needle.to_s)}%"
          scope = scope.where('LOWER(projects.name) LIKE LOWER(:p) OR LOWER(projects.identifier) LIKE LOWER(:p)', p: pattern)
        end

        limit = limit_for(arguments)
        total = scope.count
        {
          total_count: total,
          returned: [total, limit].min,
          projects: scope.limit(limit).map { |project| summarise(project) }
        }
      end

      def summarise(project)
        {
          id: project.id,
          identifier: project.identifier,
          name: project.name,
          description: project.description,
          status: project.status,
          is_public: project.is_public?,
          parent_id: project.parent_id,
          created_on: iso(project.created_on),
          updated_on: iso(project.updated_on)
        }
      end
    end
  end
end
