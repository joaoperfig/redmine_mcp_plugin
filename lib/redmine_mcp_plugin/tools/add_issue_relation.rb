# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class AddIssueRelation < Tool
      # IssueRelation::TYPES, spelled out. The schema is built when this class
      # loads; referencing a core model constant here would tie eager loading
      # of the plugin to the load order of core models.
      RELATION_TYPES = %w[relates duplicates duplicated blocks blocked precedes follows
                          copied_to copied_from].freeze

      tool 'add_issue_relation',
           title: 'Add issue relation',
           description: 'Link two issues. The type reads from issue_id: "blocks" means issue_id blocks issue_to_id.',
           permission: :manage_issue_relations,
           write: true,
           schema: {
             'type' => 'object',
             'properties' => {
               'issue_id' => { 'type' => 'integer', 'description' => 'Issue the relation is added to.' },
               'issue_to_id' => { 'type' => 'integer', 'description' => 'The other issue.' },
               'relation_type' => { 'type' => 'string', 'enum' => RELATION_TYPES,
                                    'description' => 'Defaults to relates.' },
               'delay' => { 'type' => 'integer', 'minimum' => 0,
                            'description' => 'Delay in days. Only meaningful for precedes and follows.' }
             },
             'required' => %w[issue_id issue_to_id],
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        issue = Issue.visible(user).find_by(id: arguments['issue_id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['issue_id'].inspect}" if issue.nil?

        other = Issue.visible(user).find_by(id: arguments['issue_to_id'].to_i)
        raise ToolError, "No visible issue with id #{arguments['issue_to_id'].inspect}" if other.nil?

        # The source project only, as core's IssueRelationsController does.
        # Visibility of the other issue is already established above.
        authorize!(:manage_issue_relations, issue.project)

        relation = IssueRelation.new(issue_from: issue, issue_to: other,
                                     relation_type: arguments['relation_type'].presence || 'relates')
        relation.delay = arguments['delay'] if arguments.key?('delay')
        # Writes the "Related to" line into both issues' history, as the UI does.
        relation.init_journals(user)
        begin
          saved = relation.save
        rescue ActiveRecord::RecordNotUnique
          # The uniqueness validation runs before core swaps a reverse type
          # (blocked -> blocks) in before_save, so an existing link asked for
          # from the other side reaches the unique index. Core's
          # IssueRelationsController rescues it the same way.
          raise ToolError, 'These issues are already related'
        end
        raise ToolError, "Could not add relation: #{relation.errors.full_messages.join('; ')}" unless saved

        # Core stores reverse types in canonical form (blocked becomes blocks,
        # with the issues swapped), so report what was stored, not what was asked.
        { id: relation.id, issue_from_id: relation.issue_from_id, issue_to_id: relation.issue_to_id,
          relation_type: relation.relation_type, delay: relation.delay }
      end
    end
  end
end
