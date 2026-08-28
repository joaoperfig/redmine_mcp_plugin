# frozen_string_literal: true

module RedmineMcpPlugin
  # Base class for every exposed tool.
  #
  # The permission model here is belt and braces, and the second belt is not
  # redundant:
  #
  #   1. `permission` is checked through User#allowed_to?, which intersects the
  #      user's role permissions with the OAuth token's scopes.
  #   2. Each tool additionally reads through core's .visible scopes.
  #
  # Both are required. Core's SQL visibility scopes go through
  # Project.allowed_to_condition, which calls role.allowed_to?(permission) with
  # NO scope argument -- so .visible honours roles but is blind to OAuth scopes.
  # Relying on .visible alone would let a token scoped to view_wiki_pages read
  # issues. Relying on allowed_to? alone would return rows from projects the
  # user is not a member of. Neither check subsumes the other.
  class Tool
    class << self
      attr_reader :mcp_name, :mcp_title, :mcp_description, :mcp_schema,
                  :mcp_permission, :mcp_write

      def tool(name, title:, description:, schema:, permission: nil, write: false)
        @mcp_name        = name.to_s
        @mcp_title       = title
        @mcp_description = description
        @mcp_schema      = schema
        @mcp_permission  = permission
        @mcp_write       = write
      end

      def write? = !!@mcp_write

      # Whether this tool should appear in tools/list for the current user.
      # tools/list is allowed to vary by the authorization presented on the
      # request -- the 2026-07-28 spec says so explicitly -- and hiding a tool
      # the caller could never successfully call is friendlier than letting a
      # model discover it and fail.
      def available_to?(user)
        return false if write? && Settings.read_only?
        return true  if mcp_permission.nil?

        user.allowed_to?(mcp_permission, nil, global: true)
      end

      def descriptor
        {
          name: mcp_name,
          title: mcp_title,
          description: mcp_description,
          inputSchema: mcp_schema
        }
      end
    end

    # `auth` carries what core does not expose. Redmine declares
    # `attr_writer :oauth_scope` on User with no matching reader, so the granted
    # scopes cannot be read back off the model once set -- the plugin has to
    # remember them itself.
    def initialize(user, auth = {})
      @user = user
      @auth = auth || {}
    end

    attr_reader :user, :auth

    def auth_mode   = @auth[:mode]
    def oauth?      = @auth[:mode] == :oauth2
    def oauth_scopes = @auth[:scopes]

    # Invoked by the dispatcher. Subclasses implement #perform.
    def call(arguments)
      klass = self.class
      raise PermissionError, 'This tool is disabled: the server is in read-only mode' if klass.write? && Settings.read_only?

      if klass.mcp_permission && !user.allowed_to?(klass.mcp_permission, nil, global: true)
        raise PermissionError, 'You do not have permission to use this tool'
      end

      perform(arguments || {})
    end

    private

    def perform(_arguments)
      raise NotImplementedError
    end

    # --- helpers available to every tool ----------------------------------

    # Confirms the user may do `permission` in `project`, honouring OAuth
    # scopes. Use this for anything scoped to one project; the .visible scopes
    # alone will not catch a scope-narrowed token.
    def authorize!(permission, project)
      raise PermissionError, 'You do not have permission to do that' unless user.allowed_to?(permission, project)
    end

    def limit_for(arguments)
      requested = arguments['limit'].presence&.to_i
      return Settings.max_results if requested.nil? || requested <= 0

      [requested, Settings.max_results].min
    end

    def fetch_project(identifier)
      raise ToolError, 'project is required' if identifier.blank?

      project = Project.visible(user).find_by(identifier: identifier.to_s) ||
                Project.visible(user).find_by(id: identifier.to_s.to_i)
      # Deliberately the same message whether the project does not exist or is
      # merely invisible: distinguishing them confirms the existence of projects
      # the caller cannot see.
      raise ToolError, "No visible project matching #{identifier.inspect}" if project.nil?

      project
    end

    def iso(time)
      time&.iso8601
    end
  end
end
