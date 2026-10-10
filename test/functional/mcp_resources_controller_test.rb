# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Covers the attachment resource surface at the HTTP boundary: the capability is
# declared without subscribe/listChanged, discovery stays constant (empty list,
# one template), and every read runs as the authenticated Redmine user. Reads
# resolve through issue and attachment visibility, answer every unavailable
# resource with the same -32602 so existence cannot be inferred, and -- in OAuth
# mode -- offer a view_issues step-up before dispatch.
class McpResourcesControllerTest < Redmine::ControllerTest
  tests McpController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :enabled_modules,
           :attachments

  # Attachment 4 is source.rb on issue 2 (ecookbook), readable by jsmith, with a
  # real fixture file on disk. Its stored content type is application/x-ruby, which
  # is not on the safe-text allowlist, so it travels the base64 blob path.
  VISIBLE_ATTACHMENT_URI = 'redmine://issues/2/attachments/4'

  def setup
    Setting.rest_api_enabled = '1'
    enable_mcp('enabled' => '1')
    set_fixtures_attachments_directory
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

  def oauth_headers(user, scopes:)
    application = Doorkeeper::Application.create!(
      name: 'MCP resources test', redirect_uri: 'https://client.example/callback', scopes: scopes
    )
    token = Doorkeeper::AccessToken.create!(
      application_id: application.id, resource_owner_id: user.id, scopes: scopes, expires_in: 7200
    )
    { 'Authorization' => "Bearer #{token.plaintext_token}" }
  end

  def read_attachment(uri, headers)
    post_mcp rpc('resources/read', { 'uri' => uri }), headers
  end

  def test_initialize_declares_resources_without_subscribe_or_list_changed
    post_mcp rpc('initialize', {
                   'protocolVersion' => '2025-06-18',
                   'capabilities' => {},
                   'clientInfo' => { 'name' => 'resources-test', 'version' => '1.0.0' }
                 }), api_key_headers(User.find(2))

    resources = json_body.dig('result', 'capabilities', 'resources')
    assert_equal({}, resources)
  end

  def test_resources_list_is_empty
    post_mcp rpc('resources/list'), api_key_headers(User.find(2))

    assert_equal [], json_body['result']['resources']
  end

  def test_resources_templates_list_publishes_the_single_attachment_template
    post_mcp rpc('resources/templates/list'), api_key_headers(User.find(2))

    templates = json_body['result']['resourceTemplates']
    assert_equal [RedmineMcpPlugin::Resources::ATTACHMENT_URI_TEMPLATE], templates.pluck('uriTemplate')
  end

  def test_resources_read_returns_a_typed_non_text_attachment_as_a_blob
    read_attachment(VISIBLE_ATTACHMENT_URI, api_key_headers(User.find(2)))

    contents = json_body['result']['contents']
    assert_equal 1, contents.size
    assert_equal VISIBLE_ATTACHMENT_URI, contents.first['uri']
    assert contents.first.key?('blob'), 'a non-text type is returned as a base64 blob'
    assert_not contents.first.key?('text')
    assert_equal 'application/x-ruby', contents.first['mimeType'], 'the resolved content type is preserved'
  end

  def test_resources_read_falls_back_to_octet_stream_for_an_untyped_attachment
    Attachment.find(4).update_columns(content_type: nil)

    read_attachment(VISIBLE_ATTACHMENT_URI, api_key_headers(User.find(2)))

    contents = json_body['result']['contents']
    assert contents.first.key?('blob'), 'an untyped attachment is returned as a base64 blob'
    assert_equal 'application/octet-stream', contents.first['mimeType']
  end

  def test_resources_read_returns_safe_text_as_text
    Attachment.find(4).update_columns(content_type: 'text/plain')

    read_attachment(VISIBLE_ATTACHMENT_URI, api_key_headers(User.find(2)))

    contents = json_body['result']['contents']
    assert contents.first.key?('text'), 'a safe UTF-8 text type is returned as text'
    assert_not contents.first.key?('blob')
    assert_equal 'text/plain', contents.first['mimeType']
  end

  def test_resources_read_never_returns_an_active_format_as_text
    # SVG and (X)HTML can carry script; the design always returns them as opaque
    # blobs so a client cannot interpret them as executable text.
    Attachment.find(4).update_columns(content_type: 'image/svg+xml')

    read_attachment(VISIBLE_ATTACHMENT_URI, api_key_headers(User.find(2)))

    contents = json_body['result']['contents']
    assert contents.first.key?('blob'), 'an active format is forced onto the blob path'
    assert_not contents.first.key?('text')
    assert_equal 'image/svg+xml', contents.first['mimeType']
  end

  def test_resources_read_uses_private_non_cacheable_hints
    read_attachment(VISIBLE_ATTACHMENT_URI, api_key_headers(User.find(2)))

    result = json_body['result']
    assert_equal 0, result['ttlMs']
    assert_equal 'private', result['cacheScope']
  end

  def test_resources_read_of_a_malformed_uri_is_not_found
    read_attachment('redmine://issues/abc/attachments/4', api_key_headers(User.find(2)))

    assert_equal(-32_602, json_body.dig('error', 'code'))
  end

  def test_resources_read_of_a_missing_attachment_is_not_found
    read_attachment('redmine://issues/2/attachments/999999', api_key_headers(User.find(2)))

    assert_equal(-32_602, json_body.dig('error', 'code'))
  end

  def test_resources_read_through_the_wrong_issue_is_not_found
    # Attachment 4 belongs to issue 2; addressing it through a different visible
    # issue must not read it.
    read_attachment('redmine://issues/3/attachments/4', api_key_headers(User.find(2)))

    assert_equal(-32_602, json_body.dig('error', 'code'))
  end

  def test_resources_read_of_a_non_issue_container_is_not_found
    # Attachment 2 is attached to a Document, not an issue.
    read_attachment('redmine://issues/1/attachments/2', api_key_headers(User.find(2)))

    assert_equal(-32_602, json_body.dig('error', 'code'))
  end

  def test_resources_read_of_an_invisible_issue_is_not_found
    issue = Issue.find(4)
    issue.update_columns(is_private: true)

    # Attachment 7 is on issue 4; user 7 cannot see the now-private issue.
    read_attachment('redmine://issues/4/attachments/7', api_key_headers(User.find(7)))

    assert_equal(-32_602, json_body.dig('error', 'code'))
  end

  def test_oauth_read_without_view_issues_scope_is_challenged
    read_attachment(VISIBLE_ATTACHMENT_URI, oauth_headers(User.find(2), scopes: 'view_project'))

    assert_response :forbidden
    # Reading an attachment is gated on view_issues; the step-up carries that scope
    # plus its one-hop same-tier correlation (view_project), never a write scope.
    assert_equal(
      'Bearer error="insufficient_scope", scope="view_issues view_project", ' \
      'resource_metadata="http://test.host/.well-known/oauth-protected-resource/mcp", ' \
      'error_description="The access token lacks the scope required for this operation"',
      response.headers['WWW-Authenticate']
    )
  end

  def test_oauth_read_with_view_issues_scope_succeeds
    read_attachment(VISIBLE_ATTACHMENT_URI, oauth_headers(User.find(2), scopes: 'view_issues'))

    assert_equal VISIBLE_ATTACHMENT_URI, json_body.dig('result', 'contents', 0, 'uri')
  end

  def test_get_issue_attachments_include_emits_resource_links_and_download_url
    post_mcp rpc('tools/call', { 'name' => 'get_issue',
                                 'arguments' => { 'id' => 2, 'include_attachments' => true } }),
             api_key_headers(User.find(2))

    result = json_body['result']
    page = result['structuredContent']['attachments']
    assert page.key?('total_count'), 'the include returns a pagination envelope'
    item = page['items'].find { |a| a['id'] == 4 }
    assert_equal VISIBLE_ATTACHMENT_URI, item['resource_uri']
    assert item['human_download_url'].to_s.start_with?('http'), 'metadata carries a browser download URL'

    link_uris = result['content'].select { |block| block['type'] == 'resource_link' }.pluck('uri')
    assert_includes link_uris, VISIBLE_ATTACHMENT_URI
  end

  def test_get_issue_attachments_include_is_paginated
    # Issue 2 holds two visible attachments (4 and 10); a limit of one must leave
    # the rest reachable rather than silently truncated.
    post_mcp rpc('tools/call', { 'name' => 'get_issue',
                                 'arguments' => { 'id' => 2, 'include_attachments' => true,
                                                  'attachments_limit' => 1 } }),
             api_key_headers(User.find(2))

    page = json_body['result']['structuredContent']['attachments']
    assert_equal 2, page['total_count']
    assert_equal 1, page['returned']
    assert_equal 1, page['items'].size
    assert page['has_more'], 'a capped page advertises more attachments'
  end
end
