# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    # Create-only: editing, closing, and destroying versions are deliberately
    # not surfaced, so this stays non-destructive and non-idempotent.
    class CreateVersion < Base
      tool_name 'create_version'
      title 'Create version'
      description 'Create a new version (milestone) in a project.'
      permission :manage_versions
      write true
      input_schema(
        'type' => 'object',
        'properties' => {
          'project' => { 'type' => %w[string integer],
                         'description' => 'Project identifier or numeric id.' },
          'name' => { 'type' => 'string', 'description' => 'Version name.' },
          'description' => { 'type' => 'string' },
          'due_date' => { 'type' => 'string', 'format' => 'date',
                          'description' => 'Target date, ISO-8601.' },
          'status' => { 'type' => 'string', 'enum' => %w[open locked closed],
                        'description' => 'Defaults to open.' },
          'sharing' => { 'type' => 'string', 'enum' => %w[none descendants hierarchy tree system],
                         'description' => 'Version sharing. Defaults to none; system sharing needs admin.' },
          'wiki_page_title' => { 'type' => 'string' }
        },
        'required' => %w[project name],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        project = fetch_project(arguments['project'])
        authorize!(:manage_versions, project)

        version = Version.new(project: project)
        version.safe_attributes = version_attributes(arguments)
        raise ToolError, "Could not create version: #{version.errors.full_messages.join('; ')}" unless version.save

        {
          id: version.id,
          name: version.name,
          project_identifier: project.identifier,
          status: version.status,
          sharing: version.sharing,
          due_date: version.due_date&.iso8601,
          created_on: iso(version.created_on)
        }
      end

      def version_attributes(arguments)
        attributes = { 'name' => arguments['name'].to_s }
        attributes['description'] = arguments['description'].to_s if arguments.key?('description')
        attributes['wiki_page_title'] = arguments['wiki_page_title'].to_s if arguments.key?('wiki_page_title')
        attributes['due_date'] = arguments['due_date'].to_s if arguments['due_date'].present?
        attributes['status'] = arguments['status'].to_s if arguments['status'].present?
        attributes['sharing'] = arguments['sharing'].to_s if arguments['sharing'].present?
        attributes
      end
    end
  end
end
