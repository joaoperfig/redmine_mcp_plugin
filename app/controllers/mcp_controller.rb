# frozen_string_literal: true

# The MCP endpoint. One path, POST/GET/DELETE, per the Streamable HTTP transport.
#
# Everything security-relevant happens here or in Authenticator; the Dispatcher
# below is pure protocol.
class McpController < ApplicationController
  # Core's CSRF check applies to cookie-authenticated requests. For the token
  # modes there is no ambient credential to forge, and an MCP client cannot
  # obtain a Rails authenticity token, so the check is skipped -- and the
  # session mode compensates with a mandatory Origin check in
  # verify_origin below. Skipping this without that check would turn the
  # optional session mode into a CSRF hole.
  skip_before_action :verify_authenticity_token

  # Core's check_if_login_required runs before our authentication and would
  # answer 302/403 for every request when login_required is on, so the
  # X-Redmine-API-Key or Bearer header would never be looked at.
  skip_before_action :check_if_login_required, raise: false

  before_action :require_endpoint_enabled
  before_action :verify_origin
  before_action :authenticate_mcp_request
  before_action :verify_protocol_version

  # POST carries every JSON-RPC message.
  def handle
    body = request.body.read.to_s

    begin
      message = JSON.parse(body)
    rescue JSON::ParserError
      return render_rpc(RedmineMcpPlugin::JsonRpc.error(nil, RedmineMcpPlugin::JsonRpc::PARSE_ERROR, 'Parse error'), :bad_request)
    end

    # Batches were removed from the protocol in 2025-06-18. Refusing them
    # explicitly beats processing element zero and silently dropping the rest.
    if message.is_a?(Array)
      return render_rpc(
        RedmineMcpPlugin::JsonRpc.error(nil, RedmineMcpPlugin::JsonRpc::INVALID_REQUEST,
                                        'JSON-RPC batching is not supported by this protocol version'),
        :bad_request
      )
    end

    unless message.is_a?(Hash) && message['method'].present?
      return render_rpc(
        RedmineMcpPlugin::JsonRpc.error(nil, RedmineMcpPlugin::JsonRpc::INVALID_REQUEST, 'Invalid Request'),
        :bad_request
      )
    end

    # `jsonrpc` is a required member and MUST be exactly "2.0". This was not
    # checked, so a request that omitted it was answered normally and the client
    # never found out its envelope was malformed.
    unless message['jsonrpc'] == '2.0'
      return render_rpc(
        RedmineMcpPlugin::JsonRpc.error(message['id'], RedmineMcpPlugin::JsonRpc::INVALID_REQUEST,
                                        'Invalid Request: jsonrpc must be "2.0"'),
        :bad_request
      )
    end

    # A notification or a response gets 202 Accepted with no body, per the
    # transport spec. notifications/initialized from an older client lands here.
    if RedmineMcpPlugin::JsonRpc.notification?(message)
      return head :accepted
    end

    dispatcher = RedmineMcpPlugin::Dispatcher.new(
      user: User.current, auth: @mcp_auth, protocol_version: @mcp_protocol_version
    )
    render_rpc(dispatcher.call(message), :ok)
  end

  # The transport allows a server with no server-to-client stream to answer GET
  # with 405. This server never pushes notifications, so that is the honest
  # answer -- and 2026-07-28 removed the GET stream from the protocol anyway.
  def stream
    render json: { error: 'This server does not offer a server-to-client stream' },
           status: :method_not_allowed
  end

  # Sessions were removed in 2026-07-28 and this server never issued one in the
  # first place, so there is nothing to delete.
  def terminate
    head :method_not_allowed
  end

  private

  def require_endpoint_enabled
    return if RedmineMcpPlugin::Settings.enabled?

    render json: { error: 'The MCP endpoint is disabled. An administrator can enable it under ' \
                          'Administration > Plugins > Redmine MCP Server.' },
           status: :forbidden
  end

  # DNS-rebinding protection, which the transport spec makes a MUST.
  #
  # Non-browser MCP clients send no Origin header, so they are unaffected. A
  # browser always sends one, which is what makes this an effective guard for
  # the cookie-authenticated mode.
  def verify_origin
    origin = request.headers['Origin'].presence
    return if origin.nil?
    return if origin == request.base_url
    return if RedmineMcpPlugin::Settings.allowed_origins.include?(origin)

    render json: { error: 'Origin not allowed' }, status: :forbidden
  end

  def authenticate_mcp_request
    result = RedmineMcpPlugin::Authenticator.new(request, self).authenticate

    unless result.ok?
      # WWW-Authenticate lets a spec-compliant MCP client discover that it
      # should start an OAuth2 flow rather than simply reporting a failure.
      if RedmineMcpPlugin::Settings.oauth2_auth? && result.status == :unauthorized
        # resource_metadata is the part a client actually needs (RFC 9728 5.1).
        # With realm alone there is nothing to discover: the client knows it
        # should present a bearer token but not which authorization server
        # issues one, which is where every automated OAuth2 flow stopped.
        response.set_header(
          'WWW-Authenticate',
          %(Bearer realm="Redmine", resource_metadata="#{oauth_protected_resource_url}")
        )
      end
      return render json: { error: result.error }, status: result.status
    end

    User.current = result.user
    @mcp_auth = { mode: result.mode, scopes: result.scopes }
  end

  # The transport requires 400 for an unsupported MCP-Protocol-Version.
  def verify_protocol_version
    header = request.headers['MCP-Protocol-Version'].presence
    @mcp_protocol_version = header || RedmineMcpPlugin::FALLBACK_PROTOCOL_VERSION
    return if header.nil? || RedmineMcpPlugin::Protocol.supported?(header)

    render json: RedmineMcpPlugin::JsonRpc.error(
      nil, RedmineMcpPlugin::JsonRpc::UNSUPPORTED_PROTOCOL_VERSION,
      "Unsupported MCP protocol version: #{header}",
      { supported: RedmineMcpPlugin::SUPPORTED_PROTOCOL_VERSIONS }
    ), status: :bad_request
  end

  def oauth_protected_resource_url
    base = request.base_url + (Redmine::Utils.relative_url_root.presence || '')
    "#{base}/.well-known/oauth-protected-resource/mcp"
  end

  def render_rpc(payload, status)
    render json: payload, status: status, content_type: 'application/json'
  end
end
