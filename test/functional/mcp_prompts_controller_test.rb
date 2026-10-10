# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers prompt discovery and rendering at the authenticated HTTP boundary.
class McpPromptsControllerTest < Redmine::ControllerTest
  tests McpController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :versions

  def setup
    Setting.rest_api_enabled = '1'
    enable_mcp('enabled' => '1')
    User.current = nil
  end

  def teardown
    Setting.clear_cache
    User.current = nil
  end

  def enable_mcp(overrides = {})
    Setting.plugin_redmine_mcp_plugin =
      RedmineMcpPlugin::Settings::DEFAULTS.merge('enabled' => '1').merge(overrides)
    Setting.clear_cache
  end

  def rpc(method, params = nil, id: 1)
    body = { jsonrpc: '2.0', id: id, method: method }
    body[:params] = params if params
    body.to_json
  end

  def post_mcp(payload, headers = {})
    @request.headers.merge!('Authorization' => nil, 'X-Redmine-API-Key' => nil, 'Origin' => nil)
    @request.headers.merge!(headers)
    post :handle, body: payload
  end

  def json_body
    JSON.parse(response.body)
  end

  def api_key_headers(user)
    { 'X-Redmine-API-Key' => user.api_key }
  end

  def test_prompts_list_is_served_to_an_authenticated_user
    post_mcp rpc('prompts/list'), api_key_headers(User.find(2))

    prompts = json_body['result']['prompts']
    names = prompts.pluck('name')
    assert_includes names, 'generate_changelog'
    assert_includes names, 'qa_ticket_history_report'

    changelog = prompts.find { |prompt| prompt['name'] == 'generate_changelog' }
    assert_equal %w[request], changelog['arguments'].pluck('name')
    assert(changelog['arguments'].none? { |arg| arg['required'] },
           'generate_changelog advertises a single optional argument')

    qa_report = prompts.find { |prompt| prompt['name'] == 'qa_ticket_history_report' }
    assert_equal %w[request], qa_report['arguments'].pluck('name')
    assert(qa_report['arguments'].none? { |arg| arg['required'] },
           'qa_ticket_history_report advertises a single optional argument')
  end

  def test_prompts_get_renders_the_changelog_skill_from_a_request
    post_mcp rpc('prompts/get', { 'name' => 'generate_changelog',
                                  'arguments' => { 'request' => 'changelog for version 1.0, Bug tracker' } }),
             api_key_headers(User.find(2))

    text = json_body['result']['messages'].first['content']['text']
    assert_includes text, 'changelog for version 1.0, Bug tracker'
    assert_includes text, 'Athena Ref.: #<issue id>'
  end

  def test_prompts_get_succeeds_with_no_arguments
    post_mcp rpc('prompts/get', { 'name' => 'generate_changelog' }), api_key_headers(User.find(2))

    assert_nil json_body['error'], 'an empty invocation must not be a -32602 error'
    text = json_body['result']['messages'].first['content']['text']
    assert_includes text, 'Athena Ref.: #<issue id>'
  end

  def test_prompts_get_succeeds_with_a_long_or_url_bearing_request
    {
      'generate_changelog' => 'https://wiki.example.com/changelog-format',
      'qa_ticket_history_report' => 'https://wiki.example.com/qa-report-format'
    }.each do |prompt_name, url|
      request = "#{'x' * 25_000} see #{url}"
      post_mcp rpc('prompts/get', { 'name' => prompt_name,
                                    'arguments' => { 'request' => request } }),
               api_key_headers(User.find(2))

      assert_nil json_body['error'], "#{prompt_name} must accept long or URL-bearing requests"
      text = json_body['result']['messages'].first['content']['text']
      assert_includes text, request
    end
  end

  def test_prompts_get_renders_the_qa_report_skill_with_no_arguments
    post_mcp rpc('prompts/get', { 'name' => 'qa_ticket_history_report' }),
             api_key_headers(User.find(2))

    assert_nil json_body['error'], 'an empty invocation must not be a -32602 error'
    text = json_body['result']['messages'].first['content']['text']
    assert_includes text, 'get_issue(include_journals: true)'
    assert_match(/no request/i, text)
  end

  def test_completion_complete_is_rejected_when_capability_is_not_advertised
    post_mcp rpc('completion/complete', {
                   'ref' => { 'type' => 'ref/prompt', 'name' => 'qa_ticket_history_report' },
                   'argument' => { 'name' => 'request', 'value' => '' }
                 }), api_key_headers(User.find(2))

    assert_response :success
    assert_equal(-32_603, json_body.dig('error', 'code'))
    assert_equal 'Server does not support completions (required for completion/complete)',
                 json_body.dig('error', 'data')
    assert_nil json_body['result']
  end
end
