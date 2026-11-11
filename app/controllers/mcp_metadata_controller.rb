# frozen_string_literal: true

# Serves the unauthenticated OAuth2 discovery documents an MCP client needs
# before it has credentials:
#
#   RFC 9728  /.well-known/oauth-protected-resource[/mcp]  what protects /mcp
#   RFC 8414  /.well-known/oauth-authorization-server      where to get a token
#
# The authorization-server document describes Redmine's Doorkeeper provider.
# Core routes take precedence if Redmine supplies this document in the future.
class McpMetadataController < ApplicationController
  # Discovery is public by design and exposes no per-user data.
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false

  before_action :require_oauth2_discoverable

  def protected_resource
    render json: {
      resource: mcp_resource_url,
      authorization_servers: [root_url_without_trailing_slash],
      scopes_supported: bootstrap_scopes,
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
      service_documentation: 'https://www.redmine.org/projects/redmine/wiki/Rest_api#OAuth2'
    }
    if RedmineMcpPlugin::Settings.dcr_enabled?
      payload[:registration_endpoint] = "#{root_url_without_trailing_slash}/oauth/registration"
    end
    methods = code_challenge_methods
    payload[:code_challenge_methods_supported] = methods if methods.any?
    render json: payload
  end

  private

  # Disabled OAuth2 endpoints must not advertise unusable discovery metadata.
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

  def supported_scopes
    return bootstrap_scopes unless defined?(Doorkeeper)

    scopes = doorkeeper_config.scopes.to_a.map(&:to_s)
    scopes.any? ? scopes : bootstrap_scopes
  rescue StandardError => e
    Rails.logger.warn("[redmine_mcp_plugin] could not enumerate OAuth2 scopes: #{e.class}: #{e.message}")
    bootstrap_scopes
  end

  def bootstrap_scopes
    RedmineMcpPlugin::OAUTH_BOOTSTRAP_SCOPES
  end

  # Doorkeeper 5.x installations expose either .config or .configuration.
  def doorkeeper_config
    Doorkeeper.respond_to?(:config) ? Doorkeeper.config : Doorkeeper.configuration
  end

  # Reports only PKCE methods the installed Doorkeeper can honor.
  def code_challenge_methods
    return [] unless defined?(Doorkeeper)

    config = doorkeeper_config
    supported =
      if config.respond_to?(:pkce_code_challenge_methods_supported)
        Array(config.pkce_code_challenge_methods_supported).map(&:to_s)
      elsif Doorkeeper::AccessGrant.column_names.include?('code_challenge')
        %w[S256]
      else
        []
      end

    # MCP requires S256; advertising plain would offer a forbidden weaker mode.
    supported & %w[S256]
  rescue StandardError => e
    Rails.logger.warn("[redmine_mcp_plugin] could not determine PKCE support: #{e.class}: #{e.message}")
    []
  end
end
