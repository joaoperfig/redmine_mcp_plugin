# frozen_string_literal: true

module RedmineMcpPlugin
  # Raised when the authenticated user may not do this at all. Deliberately a
  # separate class from ToolError so it can never be confused with a retryable
  # condition, and so the message can be kept uniform -- a permission error
  # whose wording varies by cause is an information leak in itself.
  class PermissionError < StandardError; end
end
