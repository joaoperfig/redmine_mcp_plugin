# frozen_string_literal: true

module RedmineMcpPlugin
  # Raised by a tool for a condition the calling model can correct: a bad
  # identifier, an out-of-range value, a missing project. Surfaces as an MCP
  # tool execution error (isError: true) rather than a JSON-RPC protocol error,
  # because the specification reserves protocol errors for malformed requests.
  class ToolError < StandardError; end
end
