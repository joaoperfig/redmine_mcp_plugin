# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers the Prompts tab of the plugin settings page: it lists database records,
# gives each row Save and Delete actions, and pages after 25 prompts.
class SettingsPromptsViewTest < Redmine::ControllerTest
  tests SettingsController

  fixtures :users

  def setup
    User.current = nil
    @request.session[:user_id] = 1
    ensure_default_prompts
  end

  def teardown
    User.current = nil
  end

  def ensure_default_prompts
    RedmineMcpPlugin::Prompts.defaults.each do |attributes|
      RedmineMcpPlugin::Prompt.find_or_create_by!(machine_name: attributes[:machine_name]) do |prompt|
        prompt.assign_attributes(attributes)
      end
    end
  end

  def get_prompts_tab(params = {})
    get :plugin, params: { id: 'redmine_mcp_plugin', tab: 'prompts' }.merge(params)
  end

  def test_prompts_tab_lists_each_stored_prompt_with_save_and_delete_actions
    prompt = RedmineMcpPlugin::Prompt.find_by!(machine_name: 'generate_changelog')

    get_prompts_tab

    assert_response :success
    assert_select 'fieldset.mcp-prompt:not(.mcp-prompt-new)', count: 2
    assert_select "input[name=?][value=?]", "prompts[#{prompt.id}][machine_name]", prompt.machine_name
    assert_select "button[formaction=?]", mcp_prompt_path(prompt) do |buttons|
      assert_equal 'Save', buttons.first.text.strip
    end
    assert_select "button[formaction=?]", delete_mcp_prompt_path(prompt) do |buttons|
      assert_equal 'Delete', buttons.first.text.strip
    end
    assert_select 'fieldset.mcp-prompt-new'
  end

  def test_prompt_textarea_starts_at_the_issue_description_size
    prompt = RedmineMcpPlugin::Prompt.find_by!(machine_name: 'generate_changelog')

    get_prompts_tab

    assert_select "textarea#prompts_#{prompt.id}_prompt[rows=?]", '20'
    assert_select "textarea#prompts_#{prompt.id}_prompt[style*=?]", 'resize: vertical'
  end

  def test_more_than_25_prompts_are_paged
    RedmineMcpPlugin::Prompt.delete_all
    26.times do |index|
      RedmineMcpPlugin::Prompt.create!(
        name: "Prompt #{index}", machine_name: "prompt_#{index}", prompt: 'Text.'
      )
    end

    get_prompts_tab
    assert_select 'fieldset.mcp-prompt:not(.mcp-prompt-new)', count: 25
    assert_select 'div.pagination a[href*="page=2"]'

    get_prompts_tab(page: 2)
    assert_select 'fieldset.mcp-prompt:not(.mcp-prompt-new)', count: 1
  end
end
