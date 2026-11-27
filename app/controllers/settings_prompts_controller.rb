# frozen_string_literal: true

# Creates, updates, and deletes the stored MCP prompts from the plugin settings
# page. The settings form owns the CSRF token and submits these actions through
# each row's Save/Delete button, so the controller accepts POST for all three
# verbs rather than requiring a nested form (which HTML forbids).
class SettingsPromptsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  require_sudo_mode :create, :update, :destroy

  def create
    prompt = RedmineMcpPlugin::Prompt.new(prompt_attributes('new'))
    save_and_redirect(prompt, :created)
  end

  def update
    prompt = RedmineMcpPlugin::Prompt.find(params[:id])
    prompt.assign_attributes(prompt_attributes(params[:id]))
    save_and_redirect(prompt, :updated)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def destroy
    prompt = RedmineMcpPlugin::Prompt.find(params[:id])
    prompt.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_prompts
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def save_and_redirect(prompt, action)
    if prompt.save
      flash[:notice] = action == :created ? l(:notice_successful_create) : l(:notice_successful_update)
    else
      flash[:error] = prompt.errors.full_messages.join(', ')
    end
    redirect_to_prompts
  end

  # Each row submits its own indexed fields because all rows share the settings
  # page's single form. The route id selects the record, so a row cannot update
  # a different prompt by changing its submitted key.
  def prompt_attributes(key)
    rows = params[:prompts]
    return {} unless rows.respond_to?(:[])

    row = rows[key]
    return {} unless row.respond_to?(:permit)

    row.permit(:name, :machine_name, :description, :prompt).to_h
  end

  def redirect_to_prompts
    options = { tab: 'prompts' }
    options[:page] = params[:prompt_page] if params[:prompt_page].present?
    redirect_to plugin_settings_path('redmine_mcp_plugin', options)
  end
end
