# frozen_string_literal: true

# Defines plugin-wide constants. Zeitwerk loads the remaining files, so each
# must define the constant implied by its path; do not add manual requires here.
module RedmineMcpPlugin
  VERSION = '0.1.0'

  # Transport revisions accepted by the controller, newest first. Older
  # revisions remain for compatibility with shipped clients.
  SUPPORTED_PROTOCOL_VERSIONS = %w[2026-07-28 2025-11-25 2025-06-18].freeze

  # Low-risk read scopes clients should request for their initial MCP handshake.
  # The two read satellites (watchers, time entries) are included as a deliberate
  # simplicity trade-off so common reads need no step-up; narrow custom tokens
  # still rely on conditional step-up. `view_private_notes` and every write scope
  # stay out. Authorization-server metadata advertises the full provider scope
  # set, not this bootstrap subset.
  OAUTH_BOOTSTRAP_SCOPES = %w[
    view_issues
    view_project
    view_wiki_pages
    view_issue_watchers
    view_time_entries
  ].freeze
end
