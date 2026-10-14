# frozen_string_literal: true

module RedmineMcpPlugin
  # Configures the MCP Ruby SDK and builds a server carrying this plugin's
  # identity and instructions. It owns how an unexpected exception is reported
  # and how the server introduces itself. The controller builds one server for
  # each authenticated request with only that caller's visible tools.
  module McpServer
    INSTRUCTIONS =
      'Redmine over MCP. Every tool runs as the authenticated Redmine user and is ' \
      'limited by that user\'s project permissions, and by the OAuth2 scopes of the ' \
      'presented token where one is used. Results are already filtered; an empty ' \
      'result means nothing visible matched, not that nothing exists.'

    # Reports an unexpected exception to the Redmine log in the SDK's two-argument
    # reporter shape. The SDK already strips the exception message from the
    # client's response -- a tool fault surfaces only as a generic "Internal
    # error" so internals (SQL, paths, record contents) cannot leak (CWE-209) --
    # which leaves the log as the only place the cause survives. Kept in the same
    # established `[redmine_mcp_plugin] Class: message` shape. The second
    # argument is the SDK's per-call reporter context, unused here.
    EXCEPTION_REPORTER = lambda do |exception, _server_context|
      Rails.logger.error(
        "[redmine_mcp_plugin] #{exception.class}: #{exception.message}\n" \
        "#{exception.backtrace&.first(15)&.join("\n")}"
      )
    end

    # Capabilities this server advertises. The `logging` entry is carried over
    # unchanged from the SDK's default set so this is not a silent capability
    # regression. `resources` is declared as a flat
    # object: issue attachments are served through `resources/read` and the single
    # published template, but the capability promises neither `listChanged` nor
    # `subscribe`, because attachment discovery is owned by `get_issue` and nothing
    # here emits change notifications. `prompts` is a flat server capability --
    # individual prompts are not gated per user, since a prompt only renders
    # instructions and the read tools it names stay independently authorized.
    CAPABILITIES = {
      tools: { listChanged: true },
      prompts: { listChanged: true },
      resources: {},
      logging: {}
    }.freeze

    module_function

    # Installs the exception reporter on the SDK's global configuration,
    # replacing its no-op default. Idempotent: a server captures this
    # configuration when it is constructed, so build calls this first.
    def configure!
      MCP.configuration.exception_reporter = EXCEPTION_REPORTER
    end

    # Builds a stateless MCP server. `tools`, `prompts`, `resource_templates`, and
    # `server_context` default empty so an initialize/ping handshake answers before
    # any tool, prompt, or resource is wired in.
    def build(tools: [], prompts: [], resource_templates: [], server_context: nil)
      configure!

      server = MCP::Server.new(
        name: 'redmine-mcp-plugin',
        title: 'Redmine',
        version: RedmineMcpPlugin::VERSION,
        instructions: INSTRUCTIONS,
        tools: tools,
        prompts: prompts,
        resource_templates: resource_templates,
        capabilities: CAPABILITIES,
        server_context: server_context
      )
      install_resource_handler(server)
      server
    end

    # Routes `resources/read` to the attachment reader. The read runs after the
    # controller has authenticated the request and set User.current, so the issue
    # and attachment visibility scopes narrow to the same caller -- OAuth scopes
    # included -- and a URI never discloses an attachment the caller cannot see.
    # The controller offers any OAuth step-up before dispatch; this handler still
    # re-checks authorization, so it is the final gate, not the only one.
    def install_resource_handler(server)
      server.resources_read_handler do |params|
        RedmineMcpPlugin::Resources.read(params, user: User.current)
      end
    end
  end
end
