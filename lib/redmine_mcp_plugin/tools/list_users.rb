# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class ListUsers < Tool
      tool 'list_users',
           title: 'List users',
           description: 'Search the users visible to the authenticated user, by name or login.',
           permission: nil,
           schema: {
             'type' => 'object',
             'properties' => {
               'name' => { 'type' => 'string', 'description' => 'Case-insensitive substring of login, first or last name.' },
               'offset' => { 'type' => 'integer', 'minimum' => 0,
                             'description' => 'Rows to skip, for paging past the server cap. Defaults to 0.' },
               'limit' => { 'type' => 'integer', 'minimum' => 1 }
             },
             'additionalProperties' => false
           }

      private

      def perform(arguments)
        # Principal.visible, not User.all. Redmine's own users list is
        # require_admin, and each role carries a users_visibility setting of
        # 'all' or 'members_of_visible_projects'. Enumerating User.all here
        # would hand the whole directory -- logins, names, last login times --
        # to any authenticated caller, which is strictly more than the same
        # user can see through the web interface or the REST API.
        scope = Principal.visible(user).where(type: 'User').active

        if (needle = arguments['name'].presence)
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(needle.to_s)}%"
          scope = scope.where(
            'LOWER(users.login) LIKE LOWER(:p) OR LOWER(users.firstname) LIKE LOWER(:p) OR LOWER(users.lastname) LIKE LOWER(:p)',
            p: pattern
          )
        end

        limit  = limit_for(arguments)
        offset = offset_for(arguments)
        rows   = scope.order(:lastname, :firstname).offset(offset).limit(limit).map do |principal|
          { id: principal.id, login: principal.login, name: principal.name }
        end
        paged(total: scope.count, offset: offset, key: :users, rows: rows)
      end
    end
  end
end
