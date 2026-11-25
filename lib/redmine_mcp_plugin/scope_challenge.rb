# frozen_string_literal: true

module RedmineMcpPlugin
  # Composes OAuth insufficient-scope challenges and owns the permission
  # correlation policy used for step-up. Correlations may bundle only scopes in
  # the challenged operation's tier: a read challenge must never introduce a
  # write scope. When adding a correlation, declare every member's tier in
  # SCOPE_TIERS; header composition enforces that all members stay in the
  # operation's tier.
  module ScopeChallenge
    ERROR_DESCRIPTION = 'The access token lacks the scope required for this operation'

    # Every Redmine permission that affects the MCP surface, mapped to its tier.
    # The map is exhaustive so the primary scope lookup can fail closed through
    # SCOPE_TIERS.fetch. `view_private_notes` filters payload visibility rather
    # than gating an operation, but it is a read scope and so is declared here.
    SCOPE_TIERS = {
      view_project: :read,
      view_issues: :read,
      view_wiki_pages: :read,
      view_issue_watchers: :read,
      view_time_entries: :read,
      view_private_notes: :read,

      admin: :write,
      add_issues: :write,
      add_issue_notes: :write,
      set_notes_private: :write,
      manage_versions: :write,
      edit_wiki_pages: :write,
      log_time: :write
    }.freeze

    # One-hop, directional correlations added to a challenge so a step-up also
    # requests the useful next permissions in the same tier. Watcher and
    # time-entry scopes point back to their issue/project foundation, but an
    # ordinary issue challenge does not pull those satellites in. `add_issue_notes`,
    # `set_notes_private`, `edit_wiki_pages`, `view_private_notes`, and `admin`
    # deliberately have no outgoing correlation: a step-up for one operation never
    # pulls in private-note or administrator authority. Private-note scopes are
    # still part of initial_scopes, so ordinary clients never need that step-up.
    # A correlated
    # grant the user's role cannot exercise is inert, since effective authority is
    # the intersection of role permissions and token scopes.
    CORRELATED_SCOPES = {
      view_project: %i[view_issues view_wiki_pages].freeze,
      view_issues: %i[view_project].freeze,
      view_wiki_pages: %i[view_project].freeze,
      view_issue_watchers: %i[view_issues view_project].freeze,
      view_time_entries: %i[view_issues view_project].freeze,

      add_issues: %i[add_issue_notes].freeze,
      manage_versions: %i[edit_wiki_pages].freeze
    }.freeze

    # Write permissions some write tools need only for certain arguments (a
    # private note through add_issue_note), so they cannot be derived from
    # mcp_permission. They are requested up front with the write tools: private
    # notes are routine on a ticket, and the user's role still decides whether
    # they can set one.
    INITIAL_WRITE_EXTRAS = %i[set_notes_private].freeze

    module_function

    # Scopes a client should request when it first authorizes, advertised in the
    # 401 challenge and in protected-resource metadata. Read-only mode keeps the
    # read bootstrap set. With writes enabled, each registered write tool's base
    # permission is added up front, because some MCP clients (claude.ai
    # connectors) surface an insufficient_scope step-up to the user instead of
    # re-authorizing, and every reconnect would then request the read set again.
    # INITIAL_WRITE_EXTRAS join them; `admin` stays step-up only.
    def initial_scopes
      return OAUTH_BOOTSTRAP_SCOPES if Settings.read_only?

      write_scopes = Registry.all.select(&:write?).filter_map(&:mcp_permission).map(&:to_sym)
      write_scopes = (write_scopes + INITIAL_WRITE_EXTRAS).uniq
      write_scopes.each do |scope|
        # Fail closed, as challenge_scopes does: only declared write-tier scopes.
        raise ArgumentError, "#{scope} is not a declared write scope" unless SCOPE_TIERS.fetch(scope) == :write
      end
      OAUTH_BOOTSTRAP_SCOPES + write_scopes.map(&:to_s)
    end

    def header(permissions:, write:, resource_metadata:)
      scopes = permissions.flat_map { |permission| challenge_scopes(permission, write: write) }.uniq
      'Bearer error="insufficient_scope", ' \
        "scope=\"#{scopes.join(' ')}\", " \
        "resource_metadata=\"#{resource_metadata}\", " \
        "error_description=\"#{ERROR_DESCRIPTION}\""
    end

    def challenge_scopes(permission, write:)
      permission = permission.to_sym
      expected_tier = write ? :write : :read
      # Fail closed: an undeclared permission raises KeyError rather than
      # silently emitting a scope with no known tier.
      unless SCOPE_TIERS.fetch(permission) == expected_tier
        raise ArgumentError, "scope set crosses the #{expected_tier} boundary"
      end

      correlated = CORRELATED_SCOPES.fetch(permission, [])
      correlated.each do |scope|
        next if SCOPE_TIERS.fetch(scope) == expected_tier

        raise ArgumentError, "scope set crosses the #{expected_tier} boundary"
      end
      [permission, *correlated]
    end
    private_class_method :challenge_scopes

    # Eager, load-time proof that the correlation map is internally consistent:
    # every key and member must be a declared scope (SCOPE_TIERS.fetch) and no
    # edge may cross its source's tier. A malformed map fails plugin load instead
    # of surfacing a bad challenge at request time.
    CORRELATED_SCOPES.each do |source, members|
      source_tier = SCOPE_TIERS.fetch(source)
      members.each do |member|
        next if SCOPE_TIERS.fetch(member) == source_tier

        raise "ScopeChallenge correlation #{source} -> #{member} crosses the #{source_tier} tier"
      end
    end
  end
end
