# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Pure-policy coverage for the OAuth scope correlation map. These assertions
# pin the invariants ticket 07 settled: the map is exhaustive and tier-consistent,
# correlations are one-hop and same-tier, challenges emit the hard-plus-correlated
# set in source-first order, and an undeclared or tier-crossing scope fails closed.
class RedmineMcpPluginScopeChallengeTest < ActiveSupport::TestCase
  Challenge = RedmineMcpPlugin::ScopeChallenge

  def test_every_correlation_key_and_member_is_a_declared_scope
    Challenge::CORRELATED_SCOPES.each do |source, members|
      assert Challenge::SCOPE_TIERS.key?(source), "correlation source #{source} is undeclared"
      members.each do |member|
        assert Challenge::SCOPE_TIERS.key?(member), "correlation member #{member} is undeclared"
      end
    end
  end

  def test_no_correlation_edge_crosses_its_source_tier
    Challenge::CORRELATED_SCOPES.each do |source, members|
      source_tier = Challenge::SCOPE_TIERS.fetch(source)
      members.each do |member|
        assert_equal source_tier, Challenge::SCOPE_TIERS.fetch(member),
                     "correlation #{source} -> #{member} crosses the #{source_tier} tier"
      end
    end
  end

  def test_read_challenge_appends_same_tier_correlations_source_first
    header = Challenge.header(
      permissions: %i[view_issues],
      write: false,
      resource_metadata: 'https://example.test/.well-known/oauth-protected-resource/mcp'
    )

    assert_equal 'view_issues view_project', scope_of(header)
  end

  def test_write_challenge_bundles_only_write_tier_scopes
    header = Challenge.header(
      permissions: %i[add_issues],
      write: true,
      resource_metadata: 'https://example.test/meta'
    )

    assert_equal 'add_issues add_issue_notes', scope_of(header)
  end

  def test_private_note_and_admin_have_no_outgoing_correlation
    refute Challenge::CORRELATED_SCOPES.key?(:view_private_notes)
    refute Challenge::CORRELATED_SCOPES.key?(:set_notes_private)
    refute Challenge::CORRELATED_SCOPES.key?(:edit_wiki_pages)
    refute Challenge::CORRELATED_SCOPES.key?(:admin)
  end

  def test_union_dedupes_scopes_across_several_permissions
    header = Challenge.header(
      permissions: %i[view_issues view_wiki_pages],
      write: false,
      resource_metadata: 'https://example.test/meta'
    )

    scopes = scope_of(header).split
    assert_equal scopes.uniq, scopes, 'challenge must not repeat a scope'
    assert_includes scopes, 'view_wiki_pages'
    assert_includes scopes, 'view_project'
  end

  def test_time_logging_is_a_write_tier_scope
    assert_equal :write, Challenge::SCOPE_TIERS.fetch(:log_time)

    header = Challenge.header(
      permissions: %i[log_time],
      write: true,
      resource_metadata: 'https://example.test/meta'
    )

    assert_equal 'log_time', scope_of(header)
  end

  def test_undeclared_permission_fails_closed
    assert_raises(KeyError) do
      Challenge.header(permissions: %i[not_a_real_permission], write: false, resource_metadata: 'x')
    end
  end

  def test_read_challenge_rejects_a_write_permission
    assert_raises(ArgumentError) do
      Challenge.header(permissions: %i[add_issues], write: false, resource_metadata: 'x')
    end
  end

  def test_initial_scopes_are_the_read_bootstrap_in_read_only_mode
    with_mcp_settings('read_only' => '1') do
      assert_equal RedmineMcpPlugin::OAUTH_BOOTSTRAP_SCOPES, Challenge.initial_scopes
    end
  end

  def test_initial_scopes_add_write_tool_scopes_when_writes_are_enabled
    with_mcp_settings('read_only' => '0') do
      assert_equal RedmineMcpPlugin::OAUTH_BOOTSTRAP_SCOPES +
                     %w[add_issues add_issue_notes manage_versions edit_wiki_pages set_notes_private],
                   Challenge.initial_scopes
    end
  end

  def test_initial_scopes_include_private_notes_in_both_modes
    with_mcp_settings('read_only' => '1') do
      assert_includes Challenge.initial_scopes, 'view_private_notes'
      assert_not_includes Challenge.initial_scopes, 'set_notes_private'
    end
    with_mcp_settings('read_only' => '0') do
      assert_includes Challenge.initial_scopes, 'view_private_notes'
      assert_includes Challenge.initial_scopes, 'set_notes_private'
    end
  end

  def test_initial_scopes_keep_admin_behind_step_up
    with_mcp_settings('read_only' => '0') do
      assert_not_includes Challenge.initial_scopes, 'admin'
    end
  end

  def test_initial_write_extras_are_declared_write_scopes
    Challenge::INITIAL_WRITE_EXTRAS.each do |scope|
      assert_equal :write, Challenge::SCOPE_TIERS.fetch(scope)
    end
  end

  private

  def with_mcp_settings(overrides)
    Setting.plugin_redmine_mcp_plugin = RedmineMcpPlugin::Settings::DEFAULTS.merge(overrides)
    Setting.clear_cache
    yield
  ensure
    Setting.clear_cache
  end

  def scope_of(header)
    header[/scope="([^"]*)"/, 1]
  end
end
