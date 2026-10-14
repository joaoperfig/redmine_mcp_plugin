# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Exercises the SDK-backed server in isolation: these build an MCP::Server
# directly and drive it through MCP::Server#handle, never touching the
# controller or the live request flow. They lock in the runtime configuration
# this migration slice introduces -- exception reporting and server identity --
# before any request is flipped onto the SDK.
class RedmineMcpPluginMcpServerTest < ActiveSupport::TestCase
  def test_build_answers_a_trivial_initialize
    server = RedmineMcpPlugin::McpServer.build

    response = server.handle(initialize_request)
    result = response[:result]

    assert_equal 1, response[:id]
    assert_equal 'redmine-mcp-plugin', result[:serverInfo][:name]
    assert_equal '2025-06-18', result[:protocolVersion]
  end

  def test_initialize_serves_the_current_instructions
    server = RedmineMcpPlugin::McpServer.build

    result = server.handle(initialize_request)[:result]

    assert_includes result[:instructions], 'authenticated Redmine user'
    assert_includes result[:instructions], 'OAuth2 scopes'
    assert_includes result[:instructions], 'Results are already filtered'
  end

  def test_build_answers_a_trivial_ping
    server = RedmineMcpPlugin::McpServer.build

    response = server.handle(ping_request)

    assert_equal 2, response[:id]
    assert_equal({}, response[:result])
  end

  # An unexpected exception inside a tool handler must reach the Redmine log (the
  # SDK's default reporter is a no-op that would swallow it) while the client
  # sees only a generic internal error -- the handler's message can carry
  # internals that must not cross the wire (CWE-209).
  def test_unexpected_tool_exception_is_logged_but_not_leaked
    secret = 'leaked-internal-detail-/var/secret'
    server = RedmineMcpPlugin::McpServer.build
    server.define_tool(name: 'boom', input_schema: { type: 'object', properties: {} }) do |**|
      raise secret
    end

    log = StringIO.new
    response = with_logger(ActiveSupport::Logger.new(log)) do
      server.handle(tool_call_request('boom'))
    end

    assert_not_includes response.to_json, secret, 'exception message must not reach the client'
    assert_equal(-32_603, response.dig(:error, :code))
    assert_includes log.string, secret, 'exception must be reported to the Redmine log'
  end

  private

  def initialize_request
    {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'test-client', version: '1.0.0' }
      }
    }
  end

  def ping_request
    { jsonrpc: '2.0', id: 2, method: 'ping', params: {} }
  end

  def tool_call_request(name)
    { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: name, arguments: {} } }
  end

  def with_logger(logger)
    original = Rails.logger
    Rails.logger = logger
    yield
  ensure
    Rails.logger = original
  end
end
