# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListWikiPages < Base
      tool_name 'list_wiki_pages'
      title 'List wiki pages'
      description "List the titles of a project's wiki pages that the authenticated user may read."
      permission :view_wiki_pages
      input_schema(
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
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        wiki    = fetch_wiki(project)

        # WikiPage has only per-record visibility checks, so filter in Ruby.
        pages  = wiki.pages.includes(:wiki).select { |page| page.visible?(user) }
        limit  = limit_for(arguments)
        offset = offset_for(arguments)
        rows   = (pages.slice(offset, limit) || []).map do |page|
          { title: page.title, version: page.content&.version, updated_on: iso(page.updated_on) }
        end
        paged(total: pages.size, offset: offset, key: :pages, rows: rows)
      end
    end
  end
end
