# frozen_string_literal: true

# The MCP specification requires a single endpoint path supporting POST and GET.
# DELETE was the session-termination verb before 2026-07-28; it is routed so a
# client that still sends it gets a clean 405 instead of a routing error page.
RedmineApp::Application.routes.draw do
  post   'mcp' => 'mcp#handle',    as: :mcp_endpoint
  get    'mcp' => 'mcp#stream'
  delete 'mcp' => 'mcp#terminate'
end
