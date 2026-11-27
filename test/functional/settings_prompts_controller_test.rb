# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers the stored-prompt management actions the plugin settings page submits
# through each row's Save and Delete buttons.
class SettingsPromptsControllerTest < Redmine::ControllerTest
  tests SettingsPromptsController

  fixtures :users

  def setup
    User.current = nil
    @request.session[:user_id] = 1
  end

  def teardown
    User.current = nil
  end

  def prompt_attributes(overrides = {})
    {
      name: 'Enter time',
      machine_name: 'enter_time',
      description: 'Draft a time entry.',
      prompt: 'Record the work.'
    }.merge(overrides)
  end

  def test_create_stores_a_new_prompt
    assert_difference -> { RedmineMcpPlugin::Prompt.count }, 1 do
      post :create, params: { prompts: { 'new' => prompt_attributes } }
    end

    assert_redirected_to plugin_settings_path('redmine_mcp_plugin', tab: 'prompts')
    assert_equal 'Enter time', RedmineMcpPlugin::Prompt.find_by!(machine_name: 'enter_time').name
  end

  def test_create_reports_validation_errors
    assert_no_difference -> { RedmineMcpPlugin::Prompt.count } do
      post :create, params: { prompts: { 'new' => prompt_attributes(machine_name: 'enter-time') } }
    end

    assert_redirected_to plugin_settings_path('redmine_mcp_plugin', tab: 'prompts')
    assert flash[:error].present?
  end

  def test_update_changes_the_selected_prompt
    prompt = RedmineMcpPlugin::Prompt.create!(prompt_attributes)
    prompt.update_column(:prompt, 'Old text.')

    post :update, params: {
      id: prompt.id,
      prompts: { prompt.id.to_s => prompt_attributes(machine_name: 'log_time', prompt: 'New text.') }
    }

    assert_redirected_to plugin_settings_path('redmine_mcp_plugin', tab: 'prompts')
    prompt.reload
    assert_equal 'log_time', prompt.machine_name
    assert_equal 'New text.', prompt.prompt
  end

  def test_destroy_removes_the_selected_prompt
    prompt = RedmineMcpPlugin::Prompt.create!(prompt_attributes)

    assert_difference -> { RedmineMcpPlugin::Prompt.count }, -1 do
      post :destroy, params: { id: prompt.id }
    end

    assert_redirected_to plugin_settings_path('redmine_mcp_plugin', tab: 'prompts')
    assert_nil RedmineMcpPlugin::Prompt.find_by(id: prompt.id)
  end

  def test_non_admin_users_are_forbidden
    @request.session[:user_id] = 2

    assert_no_difference -> { RedmineMcpPlugin::Prompt.count } do
      post :create, params: { prompts: { 'new' => prompt_attributes } }
    end

    assert_response :forbidden
  end
end
