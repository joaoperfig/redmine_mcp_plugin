# frozen_string_literal: true

# Keep all transport verbs on one endpoint. DELETE remains routed so older
# session-aware clients receive an explicit HTTP 405 response.
RedmineApp::Application.routes.draw do
  post   'mcp' => 'mcp#handle',    as: :mcp_endpoint
  get    'mcp' => 'mcp#stream'
  delete 'mcp' => 'mcp#terminate'

  # Stored prompt records are edited from the plugin settings page, whose single
  # form submits each row's Save/Delete button here. POST is used for update and
  # delete so those buttons work without a nested form or a _method field that
  # would also affect the settings form's own Apply action.
  post 'settings/plugin/redmine_mcp_plugin/prompts' => 'settings_prompts#create',
       as: :mcp_prompts
  post 'settings/plugin/redmine_mcp_plugin/prompts/:id/delete' => 'settings_prompts#destroy',
       as: :delete_mcp_prompt
  post 'settings/plugin/redmine_mcp_plugin/prompts/:id' => 'settings_prompts#update',
       as: :mcp_prompt

  # RFC 9728 defines both spellings of the protected-resource document: the
  # path-suffixed form and the plain form used by existing clients.
  get '.well-known/oauth-protected-resource'     => 'mcp_metadata#protected_resource'
  get '.well-known/oauth-protected-resource/mcp' => 'mcp_metadata#protected_resource'
  get '.well-known/oauth-authorization-server'   => 'mcp_metadata#authorization_server'

  # Expose only RFC 7591 registration from doorkeeper-openid_connect; the
  # module owns lazy loading and per-request policy.
  if RedmineMcpPlugin::DynamicClientRegistration.available?
    RedmineMcpPlugin::DynamicClientRegistration.configure!
    use_doorkeeper_openid_connect do
      skip_controllers :userinfo, :discovery
    end
  end
end
