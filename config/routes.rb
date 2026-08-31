# frozen_string_literal: true

# The MCP specification requires a single endpoint path supporting POST and GET.
# DELETE was the session-termination verb before 2026-07-28; it is routed so a
# client that still sends it gets a clean 405 instead of a routing error page.
RedmineApp::Application.routes.draw do
  post   'mcp' => 'mcp#handle',    as: :mcp_endpoint
  get    'mcp' => 'mcp#stream'
  delete 'mcp' => 'mcp#terminate'

  # OAuth2 discovery. A client reads these unauthenticated, before it has a
  # token, to find out where to get one. See McpMetadataController.
  #
  # RFC 9728 defines both spellings of the protected-resource document: the
  # path-suffixed form for a resource that is not at the root, and the plain
  # form that clients in the field request anyway. Serving both costs a line.
  get '.well-known/oauth-protected-resource'     => 'mcp_metadata#protected_resource'
  get '.well-known/oauth-protected-resource/mcp' => 'mcp_metadata#protected_resource'
  get '.well-known/oauth-authorization-server'   => 'mcp_metadata#authorization_server'
end
