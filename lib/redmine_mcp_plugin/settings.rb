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
      # Write scopes OAuth clients request at sign-in when read-only is off.
      # An explicit list, never derived from the registered tools: every OAuth
      # application must allow each requested scope or Doorkeeper refuses the
      # sign-in with invalid_scope, so a plugin upgrade that adds a write tool
      # must not change what clients ask for. A new tool's scope is requested
      # only after an administrator ticks it. These are the scopes requested
      # before that rule existed, so upgraded installs keep asking for them.
      'sign_in_write_scopes' => %w[add_issues add_issue_notes manage_versions edit_wiki_pages
                                   set_notes_private].freeze,
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

      # Settings saved before this key existed lack it, so they get the
      # default. A form save with every box unticked stores [""], which is an
      # empty selection rather than a missing one.
      def sign_in_write_scopes
        raw = all['sign_in_write_scopes']
        raw = DEFAULTS['sign_in_write_scopes'] if raw.nil?
        Array(raw).map { |scope| scope.to_s.strip }.reject(&:empty?).uniq.map(&:to_sym)
      end

      # Lets the caller distinguish a configuration error from bad credentials.
      def any_auth_mode?
        oauth2_auth? || api_key_auth? || basic_auth? || session_auth?
      end

      # Text an administrator edits on the plugin settings page, such as the
      # server instructions or a tool description, or +default+ when the stored
      # value is blank. The settings form blanks a field left at its default
      # before saving, so the built-in text, and any later release's changes to
      # it, stay in force until someone edits it. Prompt bodies are stored in
      # their own table instead. Browsers submit textareas with CRLF line
      # breaks; served text uses LF. Pass +settings+ from one Settings.all when
      # reading many keys at once.
      def text(key, default, settings = all)
        value = settings[key].to_s.gsub("\r\n", "\n")
        value.strip.empty? ? default : value
      end

      def server_instructions
        text('server_instructions', McpServer::INSTRUCTIONS)
      end
    end
  end
end
