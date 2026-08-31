# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListWikiPages < Tool
      tool 'list_wiki_pages',
           title: 'List wiki pages',
           description: "List the titles of a project's wiki pages that the authenticated user may read.",
           permission: :view_wiki_pages,
           schema: {
             'type' => 'object',
             'properties' => {
               'project' => { 'type' => %w[string integer],
                             'description' => 'Project identifier or numeric id.' },
               'offset' => { 'type' => 'integer', 'minimum' => 0,
                             'description' => 'Rows to skip, for paging past the server cap. Defaults to 0.' },
               'limit' => { 'type' => 'integer', 'minimum' => 1 }
             },
             'required' => %w[project],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        wiki    = fetch_wiki(project)

        # WikiPage has no .visible SQL scope in core -- only a per-record
        # visible?, which checks the page's protection and the project's
        # permissions. Filter in Ruby rather than inventing a scope of our own.
        pages  = wiki.pages.includes(:wiki).select { |page| page.visible?(user) }
        limit  = limit_for(arguments)
        offset = offset_for(arguments)
        # slice returns nil, not [], once offset runs past the end.
        rows   = (pages.slice(offset, limit) || []).map do |page|
          { title: page.title, version: page.content&.version, updated_on: iso(page.updated_on) }
        end
        paged(total: pages.size, offset: offset, key: :pages, rows: rows)
      end
    end
  end
end
