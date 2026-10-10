# frozen_string_literal: true

module RedmineMcpPlugin
  # Represents a non-retryable authorization failure. It remains distinct from
  # ToolError so callers receive a uniform message that leaks no policy details.
  class PermissionError < StandardError; end
end
