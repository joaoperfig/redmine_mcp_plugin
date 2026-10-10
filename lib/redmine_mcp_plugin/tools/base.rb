# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    # Base class for exposed tools, now a thin layer over the MCP SDK's
    # `MCP::Tool`. Subclasses declare name, title, description and input schema
    # through the SDK DSL and add this plugin's authorization metadata through
    # `permission`/`write`/`destructive`.
    #
    # Permissioned record operations combine two authorization layers:
    #
    #   1. `permission` is checked through User#allowed_to?. Discovery checks the
    #      user's role alone, while execution also applies the OAuth token's
    #      narrower scopes.
    #   2. Record access additionally reads through core's .visible scopes.
    #
    # Redmine visibility scopes honor roles but not OAuth scopes, while
    # User#allowed_to? alone does not filter invisible records.
    #
    # Authorization is enforced with three locks:
    #
    #   * Discovery lock: `available_to?` decides whether the tool is mounted on
    #     the per-request server at all. It ignores OAuth scope narrowing so a
    #     role-permitted tool remains discoverable for step-up, while a tool the
    #     user's role denies stays out of discovery.
    #   * HTTP lock: McpController authorizes registered tools/call requests and
    #     owns role/read-only 403s and OAuth scope challenges.
    #   * Execution backstop: `run` re-checks read-only and permission before the
    #     tool body, defending against a controller bug or policy race.
    class Base < MCP::Tool
      # Private sentinel so the class-level accessors below can tell "read the
      # value" from "set it to nil" (a valid permission value). Not reusing
      # MCP::Tool's own NOT_SET, which lives on its singleton and is not meant
      # to be shared.
      NOT_SET = Object.new
      private_constant :NOT_SET

      # One stable refusal message for the execution lock, regardless of which
      # check tripped. A message that varied by cause (read-only vs. missing
      # permission) would be an information leak.
      UNAVAILABLE = 'This tool is not available'

      class << self
        # Permission required to see and run this tool, or nil for a tool every
        # authenticated user may use. Called with no argument it reads the value.
        def permission(value = NOT_SET)
          return @mcp_permission if value.equal?(NOT_SET)

          @mcp_permission = value
        end

        # Marks the tool as mutating the Redmine database. Read with no argument.
        def write(value = NOT_SET)
          return !!@mcp_write if value.equal?(NOT_SET)

          @mcp_write = value
        end

        # Marks the tool as doing destructive, non-idempotent work. Advisory:
        # clients read it to decide whether a call needs confirming.
        def destructive(value = NOT_SET)
          return !!@mcp_destructive if value.equal?(NOT_SET)

          @mcp_destructive = value
        end

        def mcp_permission = @mcp_permission
        def write?         = !!@mcp_write
        def destructive?   = !!@mcp_destructive

        # Permissions required by this invocation. Tools with argument-dependent
        # authority override this so the HTTP gate can challenge for the whole
        # operation before execution begins.
        def required_permissions(_arguments = {})
          [mcp_permission].compact
        end

        # Whether this tool should appear in tools/list for the current user and
        # be mounted on the request's server (the discovery lock). tools/list is
        # allowed to vary by the authorization presented on the request -- the
        # 2026-07-28 spec says so explicitly -- and hiding a tool the caller
        # could never successfully call is friendlier than letting a model
        # discover it and fail.
        def available_to?(user, oauth_scopes:)
          return false if write? && Settings.read_only?

          role_allows?(user, oauth_scopes: oauth_scopes)
        end

        # Checks the declared permission without OAuth scope narrowing, then
        # restores the exact scopes retained by the authentication context.
        def role_allows?(user, oauth_scopes:, permissions: required_permissions)
          return true if permissions.empty?

          user.oauth_scope = nil
          begin
            permissions.all? { |permission| user.allowed_to?(permission, nil, global: true) }
          ensure
            user.oauth_scope = oauth_scopes
          end
        end

        # Whether assigned and built-in roles can grant every permission without
        # relying on administrator authority. An OAuth administrator needs the
        # admin scope when this route cannot make the operation actionable.
        def permission_scopes_can_authorize?(user, permissions: required_permissions)
          roles = user.roles.to_a | [user.builtin_role]
          permissions.all? do |permission|
            roles.any? { |role| role.allowed_to?(permission) }
          end
        end

        # The SDK's entry point is a class method receiving validated arguments
        # as keywords plus the per-request `server_context`. Identity and OAuth
        # scopes travel in that context; this instantiates a per-request runner
        # so the instance-side helpers keep reading them off `@user`/`@auth`.
        def call(server_context:, **args)
          new(server_context[:user], server_context[:auth] || {}).run(args)
        end

        # Annotations the SDK emits. Derived from `write`/`destructive` so there
        # is a single source of truth and the hints cannot drift from the gate;
        # an explicit `annotations` DSL call still wins. Clients read these to
        # decide whether a call needs confirming, so omitting them would make a
        # read-only lookup look exactly like a destructive write.
        def annotations(*args)
          return annotations_value if args.empty?

          super
        end

        def annotations_value
          @annotations_value || default_annotations
        end

        private

        def default_annotations
          MCP::Tool::Annotations.new(
            read_only_hint: !write?,
            destructive_hint: destructive?,
            idempotent_hint: !write?
          )
        end
      end

      # `auth` carries what core does not expose. Redmine declares
      # `attr_writer :oauth_scope` on User with no matching reader, so the
      # granted scopes cannot be read back off the model once set -- the plugin
      # has to remember them itself.
      def initialize(user, auth = {})
        super()
        @user = user
        @auth = auth || {}
      end

      attr_reader :user, :auth

      def auth_mode    = @auth[:mode]
      def oauth?       = @auth[:mode] == :oauth2
      def oauth_scopes = @auth[:scopes]

      # Runs one tool call and returns an `MCP::Tool::Response`. The SDK has
      # already validated arguments against the schema by this point, so this
      # repeats the execution policy as a backstop and runs the body.
      def run(arguments)
        klass = self.class
        arguments = arguments.to_h.deep_stringify_keys
        return refusal if klass.write? && Settings.read_only?
        return refusal unless klass.required_permissions(arguments).all? do |permission|
          user.allowed_to?(permission, nil, global: true)
        end

        success(perform(arguments))
      rescue ToolError, PermissionError => e
        # Actionable, caller-scoped refusals stay inside a successful JSON-RPC
        # result as an error tool response; only unexpected exceptions propagate
        # to the SDK, which sanitizes them and reports them to the log.
        failure(e.message)
      end

      private

      def perform(_arguments)
        raise NotImplementedError
      end

      def success(payload)
        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(payload) }, *content_blocks(payload)],
          structured_content: payload
        )
      end

      # Extra MCP content blocks a tool emits alongside the JSON text block, such
      # as the resource_link blocks that point at an issue's attachment bytes.
      # None by default, so an ordinary tool response is unchanged.
      def content_blocks(_payload)
        []
      end

      def failure(text)
        MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
      end

      def refusal = failure(UNAVAILABLE)

      # Confirms the user may do `permission` in `project`, honouring OAuth
      # scopes. Use this for anything scoped to one project; the .visible scopes
      # alone will not catch a scope-narrowed token.
      # ToolError, not PermissionError: this one is scoped to a single project,
      # so the caller can act on it by asking about a different project. Keep the
      # wording uniform because a message that varies by cause is an information
      # leak.
      def authorize!(permission, project)
        raise ToolError, 'You do not have permission to do that' unless user.allowed_to?(permission, project)
      end

      # Applies the administrator's ceiling and clamps to one in case a tool's
      # schema omits its minimum, preventing invalid limits from reaching Rails.
      def limit_for(arguments)
        requested = arguments['limit'].presence&.to_i
        return Settings.max_results if requested.nil?

        [[requested, 1].max, Settings.max_results].min
      end

      # Clamps to zero when a tool's schema omits the offset minimum.
      def offset_for(arguments)
        [arguments['offset'].presence&.to_i || 0, 0].max
      end

      # Uses one pagination envelope so capped result sets remain reachable.
      def paged(total:, offset:, key:, rows:)
        {
          total_count: total,
          returned: rows.size,
          offset: offset,
          has_more: offset + rows.size < total,
          key => rows
        }
      end

      def fetch_project(identifier)
        raise ToolError, 'project is required' if identifier.blank?

        project = Project.visible(user).find_by(identifier: identifier.to_s) ||
                  Project.visible(user).find_by(id: identifier.to_s.to_i)
        # Deliberately the same message whether the project does not exist or is
        # merely invisible: distinguishing them confirms the existence of
        # projects the caller cannot see.
        raise ToolError, "No visible project matching #{identifier.inspect}" if project.nil?

        project
      end

      # Checks module availability before permission so a disabled wiki reports
      # its actual cause; visible project metadata already exposes enabled
      # modules.
      def fetch_wiki(project)
        unless project.module_enabled?(:wiki)
          raise ToolError, "The wiki module is not enabled for project #{project.identifier}"
        end

        authorize!(:view_wiki_pages, project)

        wiki = project.wiki
        raise ToolError, "Project #{project.identifier} has no wiki" if wiki.nil? || !wiki.visible?(user)

        wiki
      end

      def iso(time)
        time&.iso8601
      end

      # Typed identity reference {id, name, type} used wherever a person or
      # group is surfaced. The type keeps a Group assignee from being mistaken
      # for a user, and the id keeps same-name principals distinguishable. nil
      # in, nil out, so an optional association can be passed straight through.
      def identity(principal)
        return nil if principal.nil?

        { id: principal.id, name: principal.name, type: principal.is_a?(Group) ? 'Group' : 'User' }
      end
    end
  end
end
