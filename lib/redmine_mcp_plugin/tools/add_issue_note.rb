# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class AddIssueNote < Base
      tool_name 'add_issue_note'
      title 'Add note to issue'
      description 'Append a note (comment) to an existing issue.'
      permission :add_issue_notes
      write true
      input_schema(
        'type' => 'object',
        'properties' => {
          'id' => { 'type' => 'integer', 'description' => 'Issue id.' },
          'notes' => { 'type' => 'string', 'description' => 'The note text.' },
          'private' => { 'type' => 'boolean',
                         'description' => 'Mark the note private. Requires the set_notes_private permission.' }
        },
        'required' => %w[id notes],
        'additionalProperties' => false
      )

      def self.required_permissions(arguments = {})
        permissions = super
        arguments['private'] == true ? permissions + %i[set_notes_private] : permissions
      end

      private

      def perform(arguments)
        issue = Issue.visible(user).find_by(id: arguments['id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['id'].inspect}" if issue.nil?

        authorize!(:add_issue_notes, issue.project)
        raise ToolError, 'notes must not be empty' if arguments['notes'].to_s.strip.empty?

        # Issue delegates private_notes= to current_journal with allow_nil, so
        # initialize the journal first or the private flag is silently dropped.
        issue.init_journal(user, arguments['notes'].to_s)

        if arguments['private']
          authorize!(:set_notes_private, issue.project)
          issue.private_notes = true
        end
        raise ToolError, "Could not add note: #{issue.errors.full_messages.join('; ')}" unless issue.save

        { issue_id: issue.id, journal_id: issue.current_journal&.id, created_on: iso(issue.current_journal&.created_on) }
      end
    end
  end
end
