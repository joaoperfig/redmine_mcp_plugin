# frozen_string_literal: true

module RedmineMcp
  # Represents a tool failure the caller can correct. It surfaces as an MCP tool
  # result with isError rather than as a JSON-RPC protocol error.
  class ToolError < StandardError; end
end
