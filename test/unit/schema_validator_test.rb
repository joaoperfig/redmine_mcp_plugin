# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpPluginSchemaValidatorTest < ActiveSupport::TestCase
  V = RedmineMcpPlugin::SchemaValidator

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'project' => { 'type' => 'string' },
      'status' => { 'type' => 'string', 'enum' => %w[open closed all] },
      'assigned_to_me' => { 'type' => 'boolean' },
      'limit' => { 'type' => 'integer', 'minimum' => 1 },
      'offset' => { 'type' => 'integer', 'minimum' => 0 }
    },
    'required' => %w[project],
    'additionalProperties' => false
  }.freeze

  def assert_rejected(arguments, expected_fragment)
    error = assert_raises(RedmineMcpPlugin::ToolError) { V.validate!(SCHEMA, arguments) }
    assert_includes error.message, expected_fragment
    error
  end

  def test_accepts_valid_arguments
    assert_nothing_raised do
      V.validate!(SCHEMA, { 'project' => 'x', 'status' => 'closed', 'limit' => 10, 'offset' => 0 })
    end
  end

  def test_missing_required_argument_is_refused
    assert_rejected({}, 'Missing required argument: project')
  end

  # The bug this class exists for. 'Closed' used to fall through to the open
  # branch and return open issues, which is indistinguishable from success.
  def test_enum_is_case_sensitive_and_refuses_near_misses
    assert_rejected({ 'project' => 'x', 'status' => 'Closed' }, 'status must be one of open, closed, all')
    assert_rejected({ 'project' => 'x', 'status' => 'New' }, 'status must be one of')
    assert_rejected({ 'project' => 'x', 'status' => '' }, 'status must be one of')
  end

  def test_enum_accepts_every_declared_value
    %w[open closed all].each do |value|
      assert_nothing_raised { V.validate!(SCHEMA, { 'project' => 'x', 'status' => value }) }
    end
  end

  def test_minimum_is_enforced
    assert_rejected({ 'project' => 'x', 'limit' => 0 }, 'limit must be at least 1')
    assert_rejected({ 'project' => 'x', 'limit' => -5 }, 'limit must be at least 1')
    assert_nothing_raised { V.validate!(SCHEMA, { 'project' => 'x', 'offset' => 0 }) }
  end

  def test_types_are_enforced
    assert_rejected({ 'project' => 'x', 'limit' => 'abc' }, 'limit must be an integer')
    assert_rejected({ 'project' => 'x', 'assigned_to_me' => 'yes' }, 'assigned_to_me must be true or false')
    assert_rejected({ 'project' => 42 }, 'project must be a string')
    assert_rejected({ 'project' => { 'a' => 1 } }, 'an object')
  end

  # Clients assembled out of shell pipelines and templates send everything as a
  # string; refusing those would break callers for no benefit.
  def test_stringified_scalars_are_accepted
    assert_nothing_raised do
      V.validate!(SCHEMA, { 'project' => 'x', 'limit' => '10', 'assigned_to_me' => 'true' })
    end
  end

  def test_unknown_arguments_are_refused_and_the_accepted_set_is_named
    error = assert_rejected({ 'project' => 'x', 'limti' => 5 }, 'Unknown argument: "limti"')
    assert_includes error.message, 'Accepted: assigned_to_me, limit, offset, project, status'
  end

  # A NUL reached the database as a bind parameter and came back as -32603
  # Internal error, which told the caller nothing at all.
  def test_control_characters_are_refused
    assert_rejected({ 'project' => "a\u0000b" }, 'control character')
    assert_rejected({ 'project' => "a\u0007b" }, 'control character')
  end

  def test_whitespace_that_is_legal_in_a_title_survives
    assert_nothing_raised { V.validate!(SCHEMA, { 'project' => "a\tb\nc" }) }
  end

  def test_nil_values_are_left_to_the_tool
    assert_nothing_raised { V.validate!(SCHEMA, { 'project' => 'x', 'status' => nil }) }
  end

  # The project arguments declare %w[string integer]: fetch_project has always
  # taken either an identifier or a numeric id.
  def test_a_list_of_types_accepts_any_of_them
    schema = { 'type' => 'object',
               'properties' => { 'project' => { 'type' => %w[string integer] } },
               'additionalProperties' => false }

    assert_nothing_raised { V.validate!(schema, { 'project' => 'main' }) }
    assert_nothing_raised { V.validate!(schema, { 'project' => 42 }) }
    assert_nothing_raised { V.validate!(schema, { 'project' => '42' }) }

    error = assert_raises(RedmineMcpPlugin::ToolError) { V.validate!(schema, { 'project' => true }) }
    assert_includes error.message, 'must be a string or an integer'
  end

  def test_empty_schema_validates_anything
    assert_nothing_raised { V.validate!(nil, { 'anything' => 1 }) }
    assert_nothing_raised { V.validate!({}, { 'anything' => 1 }) }
  end
end
