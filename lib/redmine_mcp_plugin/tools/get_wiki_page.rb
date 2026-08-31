# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class GetWikiPage < Tool
      tool 'get_wiki_page',
           title: 'Get wiki page',
           description: 'Fetch the text of one wiki page.',
           permission: :view_wiki_pages,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => %w[string integer],
                             'description' => 'Project identifier or numeric id.' },
               'title' => { 'type' => 'string', 'description' => 'Wiki page title.' }
             },
             'required' => %w[project title],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        wiki    = fetch_wiki(project)

        page = wiki.find_page(arguments['title'].to_s)
        raise ToolError, "No wiki page titled #{arguments['title'].inspect}" if page.nil? || !page.visible?(user)

        {
          title: page.title,
          project_identifier: project.identifier,
          version: page.content&.version,
          text: page.content&.text,
          updated_on: iso(page.updated_on)
        }
      end
    end
  end
end
