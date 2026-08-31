# frozen_string_literal: true

# OAuth2 discovery documents for the MCP endpoint.
#
# Without these an MCP client cannot start an OAuth2 flow on its own. It posts
# to /mcp, gets 401, and has nowhere to look: the bare `WWW-Authenticate: Bearer
# realm="Redmine"` names no authorization server. So the recommended auth mode
# was reachable only by a human pasting a token in by hand.
#
# Two documents, both unauthenticated by necessity -- a client reads them before
# it has any credential:
#
#   RFC 9728  /.well-known/oauth-protected-resource[/mcp]  what protects /mcp
#   RFC 8414  /.well-known/oauth-authorization-server      where to get a token
#
# The second describes Redmine core's own Doorkeeper provider rather than
# anything this plugin implements. Redmine does not publish it, and a client
# that cannot find token_endpoint cannot proceed. Should a later Redmine start
# serving it, core's routes are drawn before plugin routes and core wins, which
# is the outcome we want.
class McpMetadataController < ApplicationController
  # A client has no session and no token at this point. That is the whole
  # purpose of these endpoints, and both documents are public by design: they
  # contain endpoint URLs and scope names, no per-user data.
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false

  before_action :require_oauth2_discoverable

  def protected_resource
    render json: {
      resource: mcp_resource_url,
      authorization_servers: [root_url_without_trailing_slash],
      scopes_supported: supported_scopes,
      bearer_methods_supported: %w[header],
      resource_name: 'Redmine MCP Server',
      resource_documentation: 'https://github.com/joaoperfig/redmine_mcp_plugin'
    }
  end

  def authorization_server
    payload = {
      issuer: root_url_without_trailing_slash,
      authorization_endpoint: "#{root_url_without_trailing_slash}/oauth/authorize",
      token_endpoint: "#{root_url_without_trailing_slash}/oauth/token",
      scopes_supported: supported_scopes,
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
      # Deliberately no registration_endpoint. Redmine has no RFC 7591 dynamic
      # client registration -- an administrator creates the application by hand
      # under Administration > Applications. Advertising an endpoint that
      # answers 404 is worse than omitting it: a client that requires
      # registration can then fail for the right reason.
      service_documentation: 'https://www.redmine.org/projects/redmine/wiki/Rest_api#OAuth2'
    }
    methods = code_challenge_methods
    payload[:code_challenge_methods_supported] = methods if methods.any?
    render json: payload
  end

  private

  # 404 rather than an empty document when there is nothing to discover: an
  # advertisement for a disabled endpoint just sends clients down a dead end.
  def require_oauth2_discoverable
    return if RedmineMcpPlugin::Settings.enabled? && RedmineMcpPlugin::Settings.oauth2_auth?

    render json: { error: 'Not found' }, status: :not_found
  end

  def root_url_without_trailing_slash
    request.base_url + (Redmine::Utils.relative_url_root.presence || '')
  end

  def mcp_resource_url
    "#{root_url_without_trailing_slash}/mcp"
  end

  # Redmine registers every permission name as an OAuth2 scope, plus 'admin',
  # which is what lets a token be strictly weaker than the user who issued it.
  # Doorkeeper's own configuration is the authoritative list; AccessControl is
  # the fallback if that ever moves.
  def supported_scopes
    return [] unless defined?(Doorkeeper)

    scopes = doorkeeper_config.scopes.to_a.map(&:to_s)
    return scopes if scopes.any?

    Redmine::AccessControl.permissions.map { |permission| permission.name.to_s } + %w[admin]
  rescue StandardError => e
    Rails.logger.warn("[redmine_mcp_plugin] could not enumerate OAuth2 scopes: #{e.class}: #{e.message}")
    []
  end

  # Doorkeeper renamed .configuration to .config and keeps both, but which one
  # is the alias has changed across 5.x. Ask for whichever this install has.
  def doorkeeper_config
    Doorkeeper.respond_to?(:config) ? Doorkeeper.config : Doorkeeper.configuration
  end

  # MCP requires clients to use PKCE, so whether Redmine's Doorkeeper supports
  # it decides whether an automated flow can work at all. Probed rather than
  # assumed: advertising S256 on an install that cannot honour it produces a
  # failure at the token endpoint, which is a much harder thing to debug than a
  # missing field here.
  def code_challenge_methods
    return [] unless defined?(Doorkeeper)

    config = doorkeeper_config
    if config.respond_to?(:pkce_code_challenge_methods_supported)
      return Array(config.pkce_code_challenge_methods_supported).map(&:to_s)
    end

    Doorkeeper::AccessGrant.column_names.include?('code_challenge') ? %w[S256] : []
  rescue StandardError => e
    Rails.logger.warn("[redmine_mcp_plugin] could not determine PKCE support: #{e.class}: #{e.message}")
    []
  end
end
