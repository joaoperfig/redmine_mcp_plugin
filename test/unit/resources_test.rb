# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Unit coverage for the attachment resource surface that does not need an
# authenticated HTTP request: the constant surface, the published template, the
# download-URL fallback, and the malformed-URI path through #read (which fails
# before any record access). Visibility, size, and byte reading are exercised at
# the HTTP boundary in the functional test.
class RedmineMcpPluginResourcesTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations,
           :enabled_modules, :attachments

  def test_resources_list_is_always_empty
    assert_equal [], RedmineMcpPlugin::Resources.all
  end

  def test_templates_publishes_only_the_attachment_template
    templates = RedmineMcpPlugin::Resources.templates

    assert_equal 1, templates.size
    assert_equal RedmineMcpPlugin::Resources::ATTACHMENT_URI_TEMPLATE, templates.first.uri_template
    assert_equal 'issue_attachment', templates.first.name
  end

  def test_read_permission_is_view_issues
    assert_equal :view_issues, RedmineMcpPlugin::Resources::READ_PERMISSION
  end

  def test_max_read_bytes_is_five_mebibytes
    assert_equal 5 * 1024 * 1024, RedmineMcpPlugin::Resources::MAX_READ_BYTES
  end

  def test_uri_pattern_matches_a_well_formed_pair_and_rejects_others
    match = RedmineMcpPlugin::Resources::ATTACHMENT_URI_PATTERN.match('redmine://issues/2/attachments/4')
    assert_equal '2', match[:issue_id]
    assert_equal '4', match[:attachment_id]

    assert_nil RedmineMcpPlugin::Resources::ATTACHMENT_URI_PATTERN.match('redmine://issues/2/attachments/')
    assert_nil RedmineMcpPlugin::Resources::ATTACHMENT_URI_PATTERN.match('redmine://issues/x/attachments/4')
    assert_nil RedmineMcpPlugin::Resources::ATTACHMENT_URI_PATTERN.match('https://example.com/file')
  end

  def test_download_url_is_a_credential_free_host_url
    url = with_settings(protocol: 'https', host_name: 'redmine.example.com') do
      RedmineMcpPlugin::Resources.download_url(Attachment.find(4))
    end

    assert_equal 'https://redmine.example.com/attachments/download/4/source.rb', url
  end

  def test_read_of_a_malformed_uri_raises_not_found_before_record_access
    assert_raises(MCP::Server::ResourceNotFoundError) do
      RedmineMcpPlugin::Resources.read({ 'uri' => 'not-a-resource-uri' }, user: User.anonymous)
    end
  end
end
