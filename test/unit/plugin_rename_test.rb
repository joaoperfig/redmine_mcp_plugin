# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require File.expand_path('../../db/migrate/20261111000000_rename_mcp_plugin_settings', __dir__)

class RedmineMcpPluginRenameTest < ActiveSupport::TestCase
  OLD_KEY = 'plugin_redmine_mcp_plugin'
  NEW_KEY = 'plugin_redmine_mcp'

  def setup
    Setting.where(name: [OLD_KEY, NEW_KEY]).delete_all
    Setting.clear_cache
    @migration = RenameMcpPluginSettings.new
  end

  def teardown
    Setting.clear_cache
  end

  def test_plugin_is_registered_under_the_new_identifier
    plugin = Redmine::Plugin.find(:redmine_mcp)
    assert_equal 'Redmine MCP', plugin.name
    assert_equal 'settings/redmine_mcp_settings', plugin.settings[:partial]
    assert_raises(Redmine::PluginNotFound) { Redmine::Plugin.find(:redmine_mcp_plugin) }
  end

  def test_upgrade_preserves_existing_configuration
    values = { 'enabled' => '1', 'read_only' => '0', 'max_results' => '25',
               'server_instructions' => 'Custom instructions', 'auth_api_key' => '0' }
    setting = legacy_setting(values)
    @migration.up
    Setting.clear_cache

    assert_equal NEW_KEY, setting.reload.name
    assert_equal values, Setting.plugin_redmine_mcp
    assert RedmineMcp::Settings.enabled?
    assert_not RedmineMcp::Settings.read_only?
    assert_not RedmineMcp::Settings.api_key_auth?
    assert_equal 25, RedmineMcp::Settings.max_results
    assert_equal 'Custom instructions', RedmineMcp::Settings.server_instructions
    assert_not Setting.exists?(name: OLD_KEY)
  end

  def test_upgrade_does_not_overwrite_new_configuration
    legacy_setting('enabled' => '1')
    Setting.create!(name: NEW_KEY, value: { 'enabled' => '0' })
    @migration.up
    Setting.clear_cache

    assert_equal({ 'enabled' => '0' }, Setting.plugin_redmine_mcp)
    assert Setting.exists?(name: OLD_KEY)
  end

  def test_fresh_install_keeps_the_endpoint_disabled
    @migration.up
    assert_not RedmineMcp::Settings.enabled?
    assert_not Setting.exists?(name: OLD_KEY)
  end

  def test_settings_rename_can_be_reversed
    setting = legacy_setting('enabled' => '1')
    @migration.up
    @migration.down
    assert_equal OLD_KEY, setting.reload.name
    assert_equal({ 'enabled' => '1' }, setting.value)
  end
  private

  def legacy_setting(values)
    Setting.new(name: OLD_KEY, value: values).tap { |setting| setting.save!(validate: false) }
  end
end
