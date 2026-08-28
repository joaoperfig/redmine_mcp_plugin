# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpPluginProtocolTest < ActiveSupport::TestCase
  P = RedmineMcpPlugin::Protocol

  def test_supported_versions_are_recognised
    RedmineMcpPlugin::SUPPORTED_PROTOCOL_VERSIONS.each do |version|
      assert P.supported?(version), "#{version} should be supported"
    end
  end

  def test_unknown_version_is_not_supported
    assert_not P.supported?('1999-01-01')
    assert_not P.supported?(nil)
  end

  def test_initialize_echoes_a_supported_version_back
    assert_equal '2025-06-18', P.negotiate_initialize('2025-06-18')
    assert_equal '2025-11-25', P.negotiate_initialize('2025-11-25')
  end

  def test_initialize_falls_back_to_preferred_for_unknown_version
    assert_equal RedmineMcpPlugin::PREFERRED_PROTOCOL_VERSION, P.negotiate_initialize('1999-01-01')
    assert_equal RedmineMcpPlugin::PREFERRED_PROTOCOL_VERSION, P.negotiate_initialize(nil)
  end

  # 2026-07-28 carries the version per-request in params._meta; it must win over
  # the transport header, which is the older revisions' mechanism.
  def test_meta_version_beats_header
    params = { '_meta' => { P::META_VERSION_KEY => '2026-07-28' } }
    assert_equal '2026-07-28', P.negotiate(params: params, header: '2025-06-18')
  end

  def test_header_used_when_no_meta
    assert_equal '2025-06-18', P.negotiate(params: {}, header: '2025-06-18')
  end

  def test_absent_version_falls_back
    assert_equal RedmineMcpPlugin::FALLBACK_PROTOCOL_VERSION, P.negotiate(params: {}, header: nil)
  end

  # Older clients ignore both of these, and the spec tells them to treat a
  # missing resultType as "complete", so decorating unconditionally is safe.
  def test_decorate_adds_result_type_and_server_info
    decorated = P.decorate(foo: 'bar')
    assert_equal 'bar', decorated[:foo]
    assert_equal 'complete', decorated[:resultType]
    assert_equal P.server_info, decorated[:_meta][P::META_SERVER_INFO_KEY]
  end

  # Declaring a capability this server cannot answer would send conformant
  # clients down a path that dead-ends.
  def test_capabilities_advertise_only_tools
    assert_equal({ tools: {} }, P.capabilities)
  end
end
