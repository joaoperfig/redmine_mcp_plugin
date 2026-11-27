# frozen_string_literal: true

class CreateRedmineMcpPrompts < ActiveRecord::Migration[7.2]
  def up
    create_table :redmine_mcp_prompts do |t|
      t.string :name, null: false
      t.string :machine_name, null: false
      t.text :description
      t.text :prompt, null: false
      t.timestamps
    end
    add_index :redmine_mcp_prompts, :machine_name, unique: true

    seed_defaults
  end

  def down
    drop_table :redmine_mcp_prompts
  end

  private

  # The two prompts that used to be hard-coded are seeded so an upgrade does not
  # silently remove them. Text previously saved on the settings page is carried
  # across, so an administrator's edits survive the move to the database.
  def seed_defaults
    settings = Setting[:plugin_redmine_mcp_plugin]
    settings = settings.respond_to?(:to_h) ? settings.to_h.with_indifferent_access : {}.with_indifferent_access

    RedmineMcpPlugin::Prompts.defaults.each do |attributes|
      prompt_text = settings["prompt_#{attributes[:machine_name]}"].to_s.strip
      prompt_text = attributes[:prompt] if prompt_text.empty?

      RedmineMcpPlugin::Prompt.create!(
        name: attributes[:name],
        machine_name: attributes[:machine_name],
        description: attributes[:description],
        prompt: prompt_text
      )
    end
  end
end
