# frozen_string_literal: true

module RedmineMcpPlugin
  # Finds the OAuth applications that would refuse a sign-in asking for the
  # scopes this plugin advertises. Doorkeeper rejects an authorization request
  # with invalid_scope when it names a scope the application does not allow,
  # so one missing scope breaks every sign-in through that application. An
  # application with no scopes of its own allows any scope the server offers.
  module OauthApplications
    module_function

    # [[application, missing scope names]] for each application that lacks
    # any of +scopes+, ordered by name. Empty when Doorkeeper is unavailable:
    # this feeds an advisory warning and must never break the settings page.
    def missing_scopes(scopes)
      wanted = scopes.map(&:to_s).uniq
      Doorkeeper.config.application_model.order(:name).filter_map do |application|
        allowed = application.scopes.to_a.map(&:to_s)
        next if allowed.empty?

        missing = wanted - allowed
        [application, missing] if missing.any?
      end
    rescue StandardError => e
      Rails.logger.warn("[redmine_mcp_plugin] could not read OAuth application scopes: #{e.class}: #{e.message}")
      []
    end
  end
end
