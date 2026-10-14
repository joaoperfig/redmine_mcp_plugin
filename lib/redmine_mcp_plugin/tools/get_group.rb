# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    # Resolves a non-builtin group by name or id, optionally with its member
    # users. This mirrors core's groups#show, which any authenticated user may
    # read subject to Group.visible, rather than the admin-only groups index.
    # Builtin groups (anonymous, non-member) are excluded through Group.givable.
    class GetGroup < Base
      tool_name 'get_group'
      title 'Get group'
      description 'Fetch a user group by name or numeric id, optionally with its member users.'
      input_schema(
        'type' => 'object',
        'properties' => {
          'group' => { 'type' => %w[string integer], 'description' => 'Group name or numeric id.' },
          'include_users' => { 'type' => 'boolean', 'description' => 'Include member users. Defaults to false.' }
        },
        'required' => %w[group],
        'additionalProperties' => false
      )

      private

      def perform(arguments)
        group = find_group(arguments['group'])
        raise ToolError, "No group matching #{arguments['group'].inspect}" if group.nil?

        payload = { id: group.id, name: group.name, type: 'Group' }
        if arguments['include_users'] == true
          payload[:users] = group.users.sort_by { |member| member.name.to_s.downcase }.map { |member| identity(member) }
        end
        payload
      end

      def find_group(identifier)
        raise ToolError, 'group is required' if identifier.blank?

        # Core's groups#show resolves through Group.visible, which applies the
        # roles' users_visibility; without it any group and its members are
        # readable. An invisible group gets the same not-found wording as a
        # missing one. named matches the group name case-insensitively; fall
        # back to an id lookup for a numeric argument.
        scope = Group.givable.visible(user)
        scope.named(identifier.to_s).first || scope.find_by(id: identifier.to_s.to_i)
      end
    end
  end
end
