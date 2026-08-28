# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class AddIssueNote < Tool
      tool 'add_issue_note',
           title: 'Add note to issue',
           description: 'Append a note (comment) to an existing issue.',
           permission: :add_issue_notes,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'id' => { 'type' => 'integer', 'description' => 'Issue id.' },
               'notes' => { 'type' => 'string', 'description' => 'The note text.' },
               'private' => { 'type' => 'boolean',
                              'description' => 'Mark the note private. Requires the set_notes_private permission.' }
             },
             'required' => %w[id notes],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue = Issue.visible(user).find_by(id: arguments['id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['id'].inspect}" if issue.nil?

        authorize!(:add_issue_notes, issue.project)
        raise ToolError, 'notes must not be empty' if arguments['notes'].to_s.strip.empty?

        # Order matters and is easy to get wrong. Issue delegates
        # private_notes= to current_journal with allow_nil: true (issue.rb:70),
        # so setting it before init_journal is silently swallowed and the note
        # is created public. Create the journal first, then mark it.
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
