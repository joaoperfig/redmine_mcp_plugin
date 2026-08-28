# frozen_string_literal: true

module RedmineMcpPlugin
  # Turns one parsed JSON-RPC message into one JSON-RPC response.
  #
  # Knows nothing about HTTP. The controller owns authentication, the Origin
  # check and status codes; this owns the protocol methods.
  class Dispatcher
    # 2026-07-28 dropped initialize/notifications/initialized and added
    # server/discover. The older revisions are still what shipped clients speak,
    # so both sets are answered and the negotiated version decides which shape
    # the client gets back.
    def initialize(user:, auth:, protocol_version:)
      @user = user
      @auth = auth
      @protocol_version = protocol_version
    end

    attr_reader :user, :auth, :protocol_version

    def call(message)
      id     = message['id']
      method = message['method'].to_s
      params = message['params'] || {}

      case method
      when 'server/discover'          then JsonRpc.result(id, discover)
      when 'initialize'               then JsonRpc.result(id, initialize_result(params))
      when 'tools/list'               then JsonRpc.result(id, Protocol.decorate(tools_list))
      when 'tools/call'               then JsonRpc.result(id, Protocol.decorate(tools_call(params)))
      when 'ping'                     then JsonRpc.result(id, {})
      else
        JsonRpc.error(id, JsonRpc::METHOD_NOT_FOUND, "Method not found: #{method}")
      end
    rescue PermissionError => e
      # A permission failure is a protocol-level refusal, not something the
      # model can fix by retrying with different arguments.
      JsonRpc.error(message['id'], JsonRpc::INVALID_REQUEST, e.message)
    rescue ToolError => e
      # Actionable: surfaced as a tool execution error so the model can correct
      # itself, per the specification's two-tier error model.
      JsonRpc.result(message['id'], Protocol.decorate(tool_error(e.message)))
    rescue StandardError => e
      Rails.logger.error("[redmine_mcp_plugin] #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")
      # Deliberately does not echo e.message: an exception from deep in Rails
      # can carry SQL, file paths or record contents the caller may not see.
      JsonRpc.error(message['id'], JsonRpc::INTERNAL_ERROR, 'Internal error')
    end

    private

    # 2026-07-28: servers MUST implement server/discover, advertising supported
    # protocol versions, capabilities and identity.
    def discover
      Protocol.decorate(
        protocolVersions: RedmineMcpPlugin::SUPPORTED_PROTOCOL_VERSIONS,
        capabilities: Protocol.capabilities,
        serverInfo: Protocol.server_info
      )
    end

    # 2025-06-18 / 2025-11-25 handshake.
    def initialize_result(params)
      requested = params['protocolVersion']
      {
        protocolVersion: Protocol.negotiate_initialize(requested),
        capabilities: Protocol.capabilities,
        serverInfo: Protocol.server_info,
        instructions: 'Redmine over MCP. Every tool runs as the authenticated Redmine user and is ' \
                      'limited by that user\'s project permissions, and by the OAuth2 scopes of the ' \
                      'presented token where one is used. Results are already filtered; an empty ' \
                      'result means nothing visible matched, not that nothing exists.'
      }
    end

    def tools_list
      {
        tools: Registry.visible_to(user).map(&:descriptor),
        # ttlMs and cacheScope are required on list results from 2026-07-28.
        # 'private' because the tool set varies per caller -- a shared cache
        # would serve one user's tool list to another.
        ttlMs: 60_000,
        cacheScope: 'private'
      }
    end

    def tools_call(params)
      name = params['name'].to_s
      tool_class = Registry.find(name, user)

      # Registry.find already filters by permission, so an unavailable tool and
      # an unknown tool are indistinguishable here -- deliberately. Saying
      # "exists but forbidden" tells a caller what the server can do for someone
      # else.
      raise PermissionError, "Unknown tool: #{name}" if tool_class.nil?

      arguments = params['arguments']
      arguments = {} if arguments.blank?
      raise ToolError, 'arguments must be an object' unless arguments.is_a?(Hash)

      payload = tool_class.new(user, auth).call(arguments.to_h)

      {
        content: [{ type: 'text', text: JSON.pretty_generate(payload) }],
        structuredContent: payload,
        isError: false
      }
    end

    def tool_error(text)
      { content: [{ type: 'text', text: text }], isError: true }
    end
  end
end
