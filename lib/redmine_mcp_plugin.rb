# frozen_string_literal: true

# Constants only.
#
# Everything else under lib/ is loaded by Zeitwerk: Redmine's PluginLoader does
# `engine_cfg.paths.add 'lib', eager_load: true` and pushes the directory into
# Rails.autoloaders.main, so each file must define exactly the constant its path
# implies, and all of them are eager-loaded at boot in production. Adding
# `require` calls here would fight the autoloader; the naming convention is the
# only mechanism needed, and a mismatch fails loudly at boot rather than
# half-loading.
module RedmineMcpPlugin
  VERSION = '0.1.0'

  # Protocol revisions this server can speak, newest first.
  #
  # 2026-07-28 removed the initialize/initialized handshake and Mcp-Session-Id
  # entirely -- every request is self-describing. That is a good fit for a Rails
  # controller, and it is what this plugin implements natively.
  #
  # The two older revisions are still what shipped clients speak, so the
  # handshake methods are kept for them. See Protocol.
  SUPPORTED_PROTOCOL_VERSIONS = %w[2026-07-28 2025-11-25 2025-06-18].freeze

  # Sent when a client offers nothing we recognise.
  PREFERRED_PROTOCOL_VERSION = '2026-07-28'

  # Per the transport spec: absent MCP-Protocol-Version header means 2025-03-26.
  # We treat it as the oldest revision we serve instead, which is wire
  # compatible for the handful of methods we implement.
  FALLBACK_PROTOCOL_VERSION = '2025-06-18'
end
