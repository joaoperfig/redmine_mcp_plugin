# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    # Create-or-update (upsert): writes a wiki page, replacing the text when the
    # page already exists. Non-destructive because wiki pages are versioned, so
    # a rewrite keeps prior revisions; idempotent because repeating the same
    # text converges on the same page. Gated on edit_wiki_pages, which core maps
    # to new/edit/update; manage_wiki is module-level admin (delete/rename/
    # protect) and does not authorize page creation.
    class CreateWikiPage < Base
      tool_name 'create_wiki_page'
      title 'Create or update wiki page'
      description 'Create a wiki page, or replace the text of an existing one.'
      permission :edit_wiki_pages
      write true
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id.' },
          'title' => { 'type' => 'string', 'description' => 'Wiki page title.' },
          'text' => { 'type' => 'string', 'description' => 'Full page text, replacing any existing text.' },
          'comments' => { 'type' => 'string', 'description' => 'Optional edit comment.' }
        },
        'required' => %w[project title text],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        unless project.module_enabled?(:wiki)
          raise ToolError, "The wiki module is not enabled for project #{project.identifier}"
        end

        authorize!(:edit_wiki_pages, project)
        wiki = project.wiki
        raise ToolError, "Project #{project.identifier} has no wiki" if wiki.nil?

        page     = wiki.find_or_new_page(arguments['title'].to_s)
        was_new  = page.new_record?
        content  = page.content || WikiContent.new(page: page)
        content.text = arguments['text'].to_s
        content.comments = arguments['comments'].presence
        content.author = user

        unless page.save_with_content(content)
          messages = (page.errors.full_messages + content.errors.full_messages).uniq
          raise ToolError, "Could not save wiki page: #{messages.join('; ')}"
        end

        {
          title: page.title,
          project_identifier: project.identifier,
          version: page.content&.version,
          created: was_new,
          updated_on: iso(page.updated_on)
        }
      end
    end
  end
end
