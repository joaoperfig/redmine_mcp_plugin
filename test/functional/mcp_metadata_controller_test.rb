# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class McpMetadataControllerTest < Redmine::ControllerTest
  tests McpMetadataController

  def setup
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS.merge(
        'enabled' => '1',
        'auth_oauth2' => '1',
        'dcr_enabled' => '1'
      )
    Setting.clear_cache
  end

  def teardown
    Setting.clear_cache
  end

  def test_authorization_server_advertises_registration_when_dcr_is_enabled
    get :authorization_server

    assert_response :success
    assert_equal 'http://test.host/oauth/registration', JSON.parse(response.body)['registration_endpoint']
  end

  def test_protected_resource_advertises_only_the_bootstrap_scopes
    get :protected_resource

    assert_response :success
    # The bootstrap subset (three core reads plus the two read satellites), not the
    # full provider scope set and no write scopes. See OAUTH_BOOTSTRAP_SCOPES.
    assert_equal %w[view_issues view_project view_wiki_pages view_issue_watchers view_time_entries],
                 JSON.parse(response.body)['scopes_supported']
  end

  def test_authorization_server_advertises_provider_supported_scopes
    get :authorization_server

    assert_response :success
    assert_includes JSON.parse(response.body)['scopes_supported'], 'add_issues'
  end

  def test_authorization_server_scope_failure_falls_back_to_bootstrap_scopes
    Doorkeeper.stubs(:config).raises(StandardError, 'configuration unavailable')

    get :authorization_server

    assert_response :success
    assert_equal %w[view_issues view_project view_wiki_pages view_issue_watchers view_time_entries],
                 JSON.parse(response.body)['scopes_supported']
  end

  def test_authorization_server_omits_registration_when_dcr_is_disabled
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS.merge('enabled' => '1', 'auth_oauth2' => '1', 'dcr_enabled' => '0')
    Setting.clear_cache

    get :authorization_server

    assert_response :success
    assert_not JSON.parse(response.body).key?('registration_endpoint')
  end
end
