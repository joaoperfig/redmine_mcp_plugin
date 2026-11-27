# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The settings page is where an administrator chooses the write scopes OAuth
# clients request at sign-in, and where a mismatch with the OAuth
# applications must show before it fails sign-ins with invalid_scope.
class RedmineMcpPluginSignInScopesSettingsTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :enabled_modules

  SCOPE_FIELD = 'settings[sign_in_write_scopes][]'

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge('enabled' => '1')
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  def test_settings_page_ticks_the_default_sign_in_scopes_only
    get :plugin, params: { id: 'redmine_mcp_plugin' }

    assert_response :success
    assert_select 'input[type=checkbox][name=?][value=add_issues][checked]', SCOPE_FIELD
    assert_select 'input[type=checkbox][name=?][value=set_notes_private][checked]', SCOPE_FIELD
    assert_select 'input[type=checkbox][name=?][value=log_time]:not([checked])', SCOPE_FIELD
  end

  def test_settings_page_warns_about_an_application_missing_a_sign_in_scope
    narrow = Doorkeeper::Application.create!(name: 'Narrow client', redirect_uri: 'https://client.example/callback',
                                             scopes: 'view_issues view_project')
    Doorkeeper::Application.create!(name: 'Complete client', redirect_uri: 'https://client.example/callback',
                                    scopes: complete_scopes.join(' '))

    get :plugin, params: { id: 'redmine_mcp_plugin' }

    assert_response :success
    assert_select 'div.warning li', text: /#{narrow.name}.*\(add_issues\)/m
    assert_select 'div.warning li', text: /Complete client/, count: 0
  end

  def test_no_warning_when_every_application_allows_the_sign_in_scopes
    Doorkeeper::Application.destroy_all
    Doorkeeper::Application.create!(name: 'Complete client', redirect_uri: 'https://client.example/callback',
                                    scopes: complete_scopes.join(' '))

    get :plugin, params: { id: 'redmine_mcp_plugin' }

    assert_response :success
    assert_select 'div.warning li', count: 0
  end

  def test_saving_stores_the_chosen_sign_in_scopes
    post :plugin, params: { id: 'redmine_mcp_plugin',
                            settings: { 'read_only' => '0', 'sign_in_write_scopes' => ['', 'add_issues', 'log_time'] } }
    Setting.clear_cache

    assert_equal %i[add_issues log_time], RedmineMcpPlugin::Settings.sign_in_write_scopes
  end

  def test_missing_scopes_lists_only_applications_lacking_a_scope
    narrow = Doorkeeper::Application.create!(name: 'Narrow client', redirect_uri: 'https://client.example/callback',
                                             scopes: 'view_issues add_issues')

    missing = RedmineMcpPlugin::OauthApplications.missing_scopes(%w[view_issues add_issues log_time])

    assert_equal [[narrow, %w[log_time]]], missing.select { |application, _| application == narrow }
  end

  private

  def complete_scopes
    RedmineMcpPlugin::OAUTH_BOOTSTRAP_SCOPES + RedmineMcpPlugin::ScopeChallenge.offered_write_scopes.map(&:to_s)
  end
end
