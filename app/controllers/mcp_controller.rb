# frozen_string_literal: true

# Serves the MCP Streamable HTTP endpoint. This controller and Authenticator own
# the security boundary; the MCP SDK handles protocol messages.
class McpController < ApplicationController
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_json_parse_error

  # Token clients cannot provide Rails CSRF tokens. Cookie authentication
  # remains protected by the mandatory Origin check in #verify_origin.
  skip_before_action :verify_authenticity_token

  # Core's check_if_login_required runs before our authentication and would
  # answer 302/403 for every request when login_required is on, so the
  # X-Redmine-API-Key or Bearer header would never be looked at.
  skip_before_action :check_if_login_required, raise: false

  before_action :require_endpoint_enabled
  before_action :verify_origin
  before_action :authenticate_mcp_request
  before_action :verify_protocol_version

  def handle
    body = request.body.read.to_s

    begin
      message = JSON.parse(body)
    rescue JSON::ParserError
      return render_json_parse_error
    end

    # Supported MCP revisions forbid batches; never process only part of one.
    if message.is_a?(Array)
      return render_rpc(
        RedmineMcp::JsonRpc.error(nil, RedmineMcp::JsonRpc::INVALID_REQUEST,
                                        'JSON-RPC batching is not supported by this protocol version'),
        :bad_request
      )
    end

    unless message.is_a?(Hash) && message['method'].present?
      return render_rpc(
        RedmineMcp::JsonRpc.error(nil, RedmineMcp::JsonRpc::INVALID_REQUEST, 'Invalid Request'),
        :bad_request
      )
    end

    unless message['jsonrpc'] == '2.0'
      return render_rpc(
        RedmineMcp::JsonRpc.error(message['id'], RedmineMcp::JsonRpc::INVALID_REQUEST,
                                        'Invalid Request: jsonrpc must be "2.0"'),
        :bad_request
      )
    end

    # A notification gets 202 Accepted with no body, per the transport spec.
    # notifications/initialized from an older client lands here.
    if RedmineMcp::JsonRpc.notification?(message)
      return head :accepted
    end

    return unless authorize_tool_call(message)
    return unless authorize_resource_read(message)
    # Prompt argument completion is neither advertised nor handled, so no such
    # request can reach data access or require a read-tier OAuth step-up.

    tools = RedmineMcp::Registry.all.select do |tool|
      tool.available_to?(User.current, oauth_scopes: @mcp_auth[:scopes])
    end
    server = RedmineMcp::McpServer.build(
      tools: tools,
      prompts: RedmineMcp::Prompts.all,
      resource_templates: RedmineMcp::Resources.templates,
      server_context: { user: User.current, auth: @mcp_auth }
    )
    render_rpc(server.handle(message.deep_symbolize_keys), :ok)
  end

  # Returns 405 because this server provides no server-to-client stream.
  def stream
    render json: { error: 'This server does not offer a server-to-client stream' },
           status: :method_not_allowed
  end

  # Returns 405 because this server never issues transport sessions.
  def terminate
    head :method_not_allowed
  end

  private

  def require_endpoint_enabled
    return if RedmineMcp::Settings.enabled?

    render json: { error: 'The MCP endpoint is disabled. An administrator can enable it under ' \
                          'Administration > Plugins > Redmine MCP.' },
           status: :forbidden
  end

  # DNS-rebinding protection, which the transport spec makes a MUST.
  #
  # MCP clients outside a browser normally send no Origin header, so they are
  # unaffected. A browser sends one, which makes this an effective guard for
  # the cookie-authenticated mode.
  def verify_origin
    origin = request.headers['Origin'].presence
    return if origin.nil?
    return if origin == request.base_url
    return if RedmineMcp::Settings.allowed_origins.include?(origin)

    render json: { error: 'Origin not allowed' }, status: :forbidden
  end

  def authenticate_mcp_request
    result = RedmineMcp::Authenticator.new(request, self).authenticate

    unless result.ok?
      if RedmineMcp::Settings.oauth2_auth? && result.status == :unauthorized
        # RFC 9728 resource metadata tells the client which authorization server
        # can issue the required bearer token.
        response.set_header(
          'WWW-Authenticate',
          "Bearer realm=\"Redmine\", resource_metadata=\"#{oauth_protected_resource_url}\", " \
          "scope=\"#{RedmineMcp::OAUTH_BOOTSTRAP_SCOPES.join(' ')}\""
        )
      end
      return render json: { error: result.error }, status: result.status
    end

    User.current = result.user
    @mcp_auth = { mode: result.mode, scopes: result.scopes }
  end

  def verify_protocol_version
    header = request.headers['MCP-Protocol-Version'].presence
    return if header.nil? || RedmineMcp::SUPPORTED_PROTOCOL_VERSIONS.include?(header)

    render json: RedmineMcp::JsonRpc.error(
      nil, RedmineMcp::JsonRpc::UNSUPPORTED_PROTOCOL_VERSION,
      "Unsupported MCP protocol version: #{header}",
      { supported: RedmineMcp::SUPPORTED_PROTOCOL_VERSIONS }
    ), status: :bad_request
  end

  def authorize_tool_call(message)
    tool = registered_called_tool(message)
    return true if tool.nil?

    if tool.write? && RedmineMcp::Settings.read_only?
      head :forbidden
      return false
    end

    permissions = tool.required_permissions(called_tool_arguments(message), user: User.current)
    return true if permissions.empty?

    unless tool.role_allows?(
      User.current, oauth_scopes: @mcp_auth[:scopes], permissions: permissions
    )
      # A broader token cannot overcome the user's role. A scope hint here
      # would invite futile consent and retry loops, so role denial is a plain
      # forbidden response with nothing for the client to union.
      head :forbidden
      return false
    end

    return true unless @mcp_auth[:mode] == :oauth2
    return true if permissions.all? { |permission| User.current.allowed_to?(permission, nil, global: true) }

    challenge_permissions = if tool.permission_scopes_can_authorize?(
                              User.current, permissions: permissions
                            )
                              permissions
                            elsif tool.write?
                              %i[admin]
                            else
                              # The admin scope could make this call succeed, but
                              # it carries write authority. A read step-up must
                              # never introduce a write-tier scope, so there is no
                              # safe challenge for this admin-only authorization.
                              head :forbidden
                              return false
                            end
    response.set_header(
      'WWW-Authenticate',
      RedmineMcp::ScopeChallenge.header(
        permissions: challenge_permissions,
        write: tool.write?,
        resource_metadata: oauth_protected_resource_url
      )
    )
    head :forbidden
    false
  end

  # Pre-authorizes a resources/read the way authorize_tool_call pre-authorizes a
  # read tool: reading any attachment is gated on :view_issues, so an OAuth token
  # too narrow for it gets a read-tier step-up challenge for that fixed scope.
  # The challenged scope is request-level, not attachment-specific, so it reveals
  # nothing about whether a given attachment exists. When the caller's role itself
  # cannot grant the permission a scope step-up is futile, so the request falls
  # through to the SDK handler, which answers every unavailable resource with the
  # same -32602. Non-OAuth modes carry full permissions and need no challenge.
  def authorize_resource_read(message)
    return true unless message['method'] == 'resources/read'
    return true unless @mcp_auth[:mode] == :oauth2
    return true if User.current.allowed_to?(RedmineMcp::Resources::READ_PERMISSION, nil, global: true)
    return true unless RedmineMcp::Resources.role_can_read?(User.current)

    response.set_header(
      'WWW-Authenticate',
      RedmineMcp::ScopeChallenge.header(
        permissions: [RedmineMcp::Resources::READ_PERMISSION],
        write: false,
        resource_metadata: oauth_protected_resource_url
      )
    )
    head :forbidden
    false
  end

  def registered_called_tool(message)
    return unless message['method'] == 'tools/call'

    params = message['params']
    return unless params.is_a?(Hash)

    RedmineMcp::Registry.all.find { |tool| tool.tool_name == params['name'] }
  end

  def called_tool_arguments(message)
    arguments = message.dig('params', 'arguments')
    arguments.is_a?(Hash) ? arguments : {}
  end

  def oauth_protected_resource_url
    base = request.base_url + (Redmine::Utils.relative_url_root.presence || '')
    "#{base}/.well-known/oauth-protected-resource/mcp"
  end

  def render_rpc(payload, status)
    render json: payload, status: status, content_type: 'application/json'
  end

  def render_json_parse_error
    # Avoid Rails rendering here: on Redmine 6.1 it may touch `params`
    # again while resolving the layout, re-raising the parse error.
    payload = RedmineMcp::JsonRpc.error(
      nil,
      RedmineMcp::JsonRpc::PARSE_ERROR,
      'Parse error'
    )
    response.status = :bad_request
    response.content_type = 'application/json'
    self.response_body = payload.to_json
  end
end
