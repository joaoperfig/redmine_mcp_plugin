# frozen_string_literal: true

module RedmineMcpPlugin
  # RFC 7591 Dynamic Client Registration, served by doorkeeper-openid_connect.
  # Only POST /oauth/registration is used; no ID token is ever minted.
  module DynamicClientRegistration
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    PUBLIC_CLIENT_AUTH_METHOD = 'none'

    class << self
      def available?
        return @available unless @available.nil?

        @available = load!
      end

      # Load during route drawing because the gem binds controllers before
      # Redmine sets base_controller when it is required at boot.
      def load!
        require 'doorkeeper/openid_connect'
        Doorkeeper::OpenidConnect::Rails::Routes.install!
        require File.join(
          Gem.loaded_specs['doorkeeper-openid_connect'].gem_dir,
          'app/controllers/doorkeeper/openid_connect/dynamic_client_registration_controller'
        )
        true
      rescue LoadError
        false
      end

      def configure!
        Doorkeeper::OpenidConnect.configure do
          # No issuer/signing_key (no ID tokens) and no scope config: Redmine core
          # already registers permission names as Doorkeeper optional_scopes, and
          # the gem validates registration scopes against that.
          dynamic_client_registration true

          authorize_dynamic_client_registration do
            RedmineMcpPlugin::DynamicClientRegistration.permitted?(params)
          end
        end
      end

      def permitted?(params)
        gate_open? && public_client?(params) && redirect_uris_acceptable?(params)
      end

      def gate_open?
        Settings.enabled? && Settings.oauth2_auth? && Settings.dcr_enabled?
      end

      # Public clients only; an omitted method defaults to confidential per RFC 7591.
      def public_client?(params)
        params[:token_endpoint_auth_method].to_s == PUBLIC_CLIENT_AUTH_METHOD
      end

      # Every redirect URI must be loopback or HTTPS, and at least one is required.
      def redirect_uris_acceptable?(params)
        uris = Array(params[:redirect_uris])
        uris.any? && uris.all? { |uri| acceptable_redirect_uri?(uri) }
      end

      def acceptable_redirect_uri?(raw)
        uri = URI.parse(raw.to_s)
        uri.scheme == 'https' || loopback?(uri)
      rescue URI::InvalidURIError
        false
      end

      def loopback?(uri)
        LOOPBACK_HOSTS.include?(uri.host.to_s.downcase.delete('[]'))
      end
    end
  end
end
