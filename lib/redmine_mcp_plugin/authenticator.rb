# frozen_string_literal: true

module RedmineMcpPlugin
  # Resolves requests through enabled Redmine authentication mechanisms without
  # introducing plugin-specific credentials or fallback to disabled modes.
  class Authenticator
    Result = Struct.new(:user, :mode, :scopes, :error, :status, keyword_init: true) do
      def ok? = user.present?
    end

    def initialize(request, controller)
      @request = request
      @controller = controller
    end

    def authenticate
      unless Settings.any_auth_mode?
        return failure('No authentication mode is enabled for the MCP endpoint', :service_unavailable)
      end

      # Core gates every non-cookie credential on this switch, and so do we:
      # an administrator who has turned the REST API off has said no to exactly
      # this class of access.
      api_modes_available = Setting.rest_api_enabled?

      if Settings.oauth2_auth? && api_modes_available && (result = try_oauth2)
        return result
      end
      if Settings.api_key_auth? && api_modes_available && (result = try_api_key)
        return result
      end
      if Settings.basic_auth? && api_modes_available && (result = try_basic)
        return result
      end
      if Settings.session_auth? && (result = try_session)
        return result
      end

      if !api_modes_available && (Settings.oauth2_auth? || Settings.api_key_auth? || Settings.basic_auth?)
        return failure('Authentication failed. The REST API is disabled in Redmine settings, ' \
                       'which disables every token-based authentication mode.', :unauthorized)
      end

      failure('Authentication failed', :unauthorized)
    end

    private

    # Resolves Redmine's OAuth2 tokens and applies their scopes to permission
    # checks, including User#admin?.
    def try_oauth2
      return nil unless bearer_token.present?

      access_token = Doorkeeper.authenticate(@request)
      return failure('Invalid or expired OAuth2 access token', :unauthorized) if access_token.nil?
      return failure('OAuth2 access token is revoked or expired', :unauthorized) unless access_token.accessible?

      user = User.active.find_by(id: access_token.resource_owner_id)
      return failure('OAuth2 token does not resolve to an active user', :unauthorized) if user.nil?

      scopes = access_token.scopes.all.map(&:to_sym)
      user.oauth_scope = scopes
      # User exposes oauth_scope as a writer only, so retain scopes separately.
      success(user, :oauth2, scopes)
    end

    # API keys carry the user's full permissions and cannot be scope-limited.
    def try_api_key
      key = @request.headers['X-Redmine-API-Key'].presence || @controller.params[:key].presence
      return nil if key.blank?

      user = User.find_by_api_key(key.to_s)
      return failure('Invalid API key', :unauthorized) unless user&.active?

      success(user, :api_key)
    end

    def try_basic
      authorization = @request.authorization.to_s
      return nil unless /\ABasic /i.match?(authorization)

      credentials = ActionController::HttpAuthentication::Basic.decode_credentials(@request).split(':', 2)
      username, password = credentials[0].to_s, credentials[1].to_s
      return nil if username.blank?

      user = User.try_to_login(username, password)

      # Core refuses username/password once two-factor is active, because a
      # password alone is then no longer the account's full credential. Same
      # rule here, or the MCP endpoint becomes a 2FA bypass.
      if user&.twofa_active?
        return failure('HTTP Basic authentication is not allowed for this account ' \
                       'because two-factor authentication is active. Use an API key or OAuth2.',
                       :unauthorized)
      end

      user ||= User.find_by_api_key(username)
      return failure('Invalid credentials', :unauthorized) unless user&.active?
      return failure('This account must change its password before it can be used', :forbidden) if user.must_change_password?

      success(user, :basic)
    end

    # Resolves the ambient browser credential after the controller's mandatory
    # Origin check.
    def try_session
      user_id = @controller.session[:user_id]
      return nil if user_id.blank?

      user = User.active.find_by(id: user_id)
      return nil if user.nil?

      success(user, :session)
    end

    def bearer_token
      authorization = @request.authorization.to_s
      return nil unless /\ABearer /i.match?(authorization)

      authorization.split(' ', 2).last
    end

    def success(user, mode, scopes = nil)
      Result.new(user: user, mode: mode, scopes: scopes)
    end

    def failure(message, status)
      Result.new(error: message, status: status)
    end
  end
end
