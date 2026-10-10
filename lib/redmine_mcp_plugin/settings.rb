# frozen_string_literal: true

module RedmineMcpPlugin
  # Provides typed access to plugin settings. Redmine returns symbol-keyed
  # defaults before the first save and string-keyed values afterward, so all
  # reads pass through an indifferent-access hash.
  module Settings
    DEFAULTS = {
      # Master switch. Off by default: installing the plugin must not open an
      # endpoint on somebody's Redmine without an explicit decision.
      'enabled' => 'false',

      # OAuth2 via Redmine core's Doorkeeper provider. The recommended mode:
      # per-user, per-scope, revocable from Administration -> Applications.
      'auth_oauth2' => 'true',
      # X-Redmine-API-Key header (or ?key=). Per-user, but carries the user's
      # full permissions with no scope narrowing.
      'auth_api_key' => 'true',
      # HTTP Basic, username/password or apikey:x. Off by default -- it sends
      # reusable credentials on every request.
      'auth_basic' => 'false',
      # An existing browser session cookie. Off by default and Origin-checked:
      # this is the only mode carrying ambient browser credentials, so it is
      # the only one exposed to cross-site request forgery.
      'auth_session' => 'false',

      'read_only' => 'true',
      # Comma/newline separated extra Origins allowed to reach the endpoint.
      # The Redmine host itself is always allowed. Requests with no Origin
      # header (the usual case outside a browser) are unaffected.
      'allowed_origins' => '',
      'max_results' => '100',
      # Dynamic client registration (RFC 7591). Off by default: when on it opens
      # an unauthenticated endpoint where any caller can register an OAuth2
      # client, so turning it on must be an explicit decision.
      'dcr_enabled' => 'false'
    }.freeze

    ABSOLUTE_MAX_RESULTS = 1000

    class << self
      def all
        raw = Setting.plugin_redmine_mcp_plugin
        (raw.respond_to?(:to_h) ? raw.to_h : {}).with_indifferent_access
      end

      def [](key)
        all[key]
      end

      # Redmine stores checkbox settings as the strings '0'/'1' once saved, but
      # DEFAULTS uses 'true'/'false'. Accept both, plus real booleans.
      def bool(key)
        value = all[key]
        case value
        when true  then true
        when false, nil then false
        else %w[1 true yes on].include?(value.to_s.strip.downcase)
        end
      end

      def enabled?      = bool('enabled')
      def read_only?    = bool('read_only')
      def oauth2_auth?  = bool('auth_oauth2')
      def api_key_auth? = bool('auth_api_key')
      def basic_auth?   = bool('auth_basic')
      def session_auth? = bool('auth_session')
      def dcr_enabled?  = bool('dcr_enabled')

      def max_results
        n = all['max_results'].to_i
        return 100 if n <= 0

        [n, ABSOLUTE_MAX_RESULTS].min
      end

      def allowed_origins
        all['allowed_origins'].to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
      end

      # Lets the caller distinguish a configuration error from bad credentials.
      def any_auth_mode?
        oauth2_auth? || api_key_auth? || basic_auth? || session_auth?
      end
    end
  end
end
