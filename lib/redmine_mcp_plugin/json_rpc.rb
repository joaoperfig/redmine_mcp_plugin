# frozen_string_literal: true

module RedmineMcpPlugin
  # Builds the pre-dispatch errors owned by the HTTP boundary and identifies
  # notifications before the SDK is invoked.
  module JsonRpc
    PARSE_ERROR      = -32_700
    INVALID_REQUEST  = -32_600

    # MCP-specification range (-32020..-32099), per the 2026-07-28 error code
    # allocation policy.
    UNSUPPORTED_PROTOCOL_VERSION = -32_022

    module_function

    def error(id, code, message, data = nil)
      err = { code: code, message: message }
      err[:data] = data unless data.nil?
      { jsonrpc: '2.0', id: id, error: err }
    end

    # A JSON-RPC notification has no id and MUST NOT be answered with a
    # response object. The transport layer turns this into 202 Accepted.
    def notification?(message)
      message.is_a?(Hash) && !message.key?('id') && message['method'].present?
    end
  end
end
