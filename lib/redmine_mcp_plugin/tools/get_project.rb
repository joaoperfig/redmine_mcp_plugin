# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class GetProject < Tool
      tool 'get_project',
           title: 'Get project',
           description: 'Fetch one project by identifier or numeric id, with its enabled modules and trackers.',
           permission: :view_project,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => %w[string integer],
                             'description' => 'Project identifier or numeric id.' }
             },
             'required' => %w[project],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        {
          id: project.id,
          identifier: project.identifier,
          name: project.name,
          description: project.description,
          homepage: project.homepage,
          status: project.status,
          is_public: project.is_public?,
          parent_id: project.parent_id,
          created_on: iso(project.created_on),
          updated_on: iso(project.updated_on),
          enabled_modules: project.enabled_module_names.sort,
          trackers: project.trackers.map { |t| { id: t.id, name: t.name } },
          # Categories and versions are cheap and are what a model needs before
          # it can create or filter an issue sensibly.
          issue_categories: project.issue_categories.map { |c| { id: c.id, name: c.name } },
          versions: project.shared_versions.map { |v| { id: v.id, name: v.name, status: v.status } }
        }
      end
    end
  end
end
