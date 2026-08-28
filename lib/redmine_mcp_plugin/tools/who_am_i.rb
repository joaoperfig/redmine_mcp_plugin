# frozen_string_literal: true

module RedmineMcpPlugin
  module Tools
    class WhoAmI < Tool
      tool 'whoami',
           title: 'Current user',
           description: 'Return the Redmine user this MCP connection is authenticated as, ' \
                        'and the OAuth2 scopes limiting it if any.',
           permission: nil,
           schema: { 'type' => 'object', 'additionalProperties' => false }

      private

      def perform(_arguments)
        {
          id: user.id,
          login: user.login,
          firstname: user.firstname,
          lastname: user.lastname,
          mail: user.mail,
          admin: user.admin?,
          authorized_by_oauth: user.authorized_by_oauth?,
          # nil rather than [] when not an OAuth session, so a client can tell
          # "no scope restrictions" apart from "a token granting nothing".
          oauth_scopes: oauth? ? Array(oauth_scopes).map(&:to_s).sort : nil,
          authentication_mode: auth_mode.to_s.presence,
          read_only_server: Settings.read_only?
        }
      end
    end
  end
end
