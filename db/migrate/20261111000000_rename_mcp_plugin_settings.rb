# frozen_string_literal: true

class RenameMcpPluginSettings < ActiveRecord::Migration[7.2]
  def up
    rename_setting('plugin_redmine_mcp_plugin', 'plugin_redmine_mcp')
  end

  def down
    rename_setting('plugin_redmine_mcp', 'plugin_redmine_mcp_plugin')
  end

  private

  # Keep the serialized value intact and never replace settings already saved
  # under the destination name. Old migration records remain as upgrade history.
  def rename_setting(source, destination)
    return if select_value("SELECT 1 FROM settings WHERE name = #{connection.quote(destination)}")

    execute <<~SQL
      UPDATE settings SET name = #{connection.quote(destination)}
      WHERE name = #{connection.quote(source)}
    SQL
  end
end
