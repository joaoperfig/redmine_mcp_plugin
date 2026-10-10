# Redmine MCP Server

Connect MCP clients to the projects, issues, wikis, and users already managed by
Redmine. The plugin runs inside the Redmine process and exposes a Streamable HTTP
endpoint at `POST /mcp`; it uses Redmine's own users, authentication, permissions,
visibility rules, settings, and database instead of creating a parallel service.

Every tool runs as the authenticated Redmine user. Redmine permissions and record
visibility limit what that user can access, and OAuth2 scopes can narrow access
further. The endpoint is disabled after installation and, once enabled, starts in
read-only mode.

## Quickstart

### 1. Install the plugin

Redmine 6.1 or later is required. From the root of a compatible Redmine checkout,
place this repository at `plugins/redmine_mcp_plugin`, install dependencies, and
run the required plugin migration:

```sh
git clone https://github.com/joaoperfig/redmine_mcp_plugin.git plugins/redmine_mcp_plugin
bundle install
bin/rails redmine:plugins:migrate NAME=redmine_mcp_plugin RAILS_ENV=production
```

Restart the Redmine application using the procedure for your deployment. Redmine
supplies the supported Ruby, Rails, database, and application-server environment;
this plugin is not a standalone Rails application.

### 2. Enable and configure the endpoint

For the shortest first connection, use a Redmine API key:

1. In **Administration > Settings > API**, enable the REST web service.
2. In **Administration > Plugins > Redmine MCP Server > Configure**, enable the
   MCP endpoint. Leave **REST API key** and **Read-only mode** enabled.
3. Save the settings, then copy an active Redmine user's API access key from that
   user's **My account** page.

The REST API setting is also required for OAuth2 and HTTP Basic authentication.
Session-cookie authentication does not depend on it.

### 3. Configure an MCP client

Point the client at the Redmine base URL followed by `/mcp` and send the user's API
key in `X-Redmine-API-Key`. A typical HTTP MCP configuration looks like this:

```json
{
  "mcpServers": {
    "redmine": {
      "type": "http",
      "url": "https://redmine.example.com/mcp",
      "headers": {
        "X-Redmine-API-Key": "YOUR_API_KEY"
      }
    }
  }
}
```

Configuration keys vary by client. If the client manages OAuth2 authorization,
omit the API-key header and use the OAuth flow described under
[Authentication](#authentication).

### 4. Verify the connection

Call the read-only `whoami` tool directly to confirm the endpoint, credentials,
and effective server mode:

```sh
curl --fail-with-body https://redmine.example.com/mcp \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --header 'MCP-Protocol-Version: 2026-07-28' \
  --header 'Mcp-Method: tools/call' \
  --header 'Mcp-Name: whoami' \
  --header 'X-Redmine-API-Key: YOUR_API_KEY' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whoami","arguments":{},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{},"io.modelcontextprotocol/clientInfo":{"name":"curl","version":"1.0"}}}}'
```

A successful JSON-RPC response contains `result.structuredContent` with the
Redmine user's identity, `authentication_mode` set to `api_key`, and
`read_only_server` set to `true`. The configured MCP client can now discover the
other tools with `tools/list`.

## Authentication

Authentication modes are independently configurable under **Administration >
Plugins > Redmine MCP Server**.

| Mode | Default | Client credential and access |
|---|---:|---|
| OAuth2 | On | Send `Authorization: Bearer TOKEN`. Redmine issues per-user tokens whose scopes can narrow the user's permissions. |
| API key | On | Send `X-Redmine-API-Key: KEY`. The key carries the user's full permissions without OAuth scope narrowing. |
| HTTP Basic | Off | Send a username and password, or an API key as the username. Accounts with two-factor authentication enabled cannot use this mode. |
| Session cookie | Off | Reuse a logged-in browser session. Intended for browser-based clients and protected by the endpoint's Origin check. |

OAuth2 clients can be registered under **Administration > Applications**. The
plugin publishes protected-resource and authorization-server metadata at:

```text
/.well-known/oauth-protected-resource
/.well-known/oauth-protected-resource/mcp
/.well-known/oauth-authorization-server
```

The protected-resource metadata and the `/mcp` authentication challenge advertise
`view_issues view_project view_wiki_pages view_issue_watchers view_time_entries`
as the minimal read bootstrap scopes for an initial client handshake. Write scopes
and `view_private_notes` are requested through step-up challenges as operations
need them.

Dynamic client registration (RFC 7591) is optional and disabled by default.
Enabling it exposes `POST /oauth/registration` so public MCP clients can register
before completing Authorization Code with PKCE.

Authentication is only the first boundary: a tool must also be allowed by the
user's Redmine permissions, OAuth scopes when present, and Redmine's record
visibility rules. See [Plugin architecture](ARCHITECTURE.md) for the request
flow, Origin policy, authorization layers, and other security invariants.

## Tools and write access

The available tool list varies with the authenticated user's access. Read-only
mode is on by default; while it is on, write tools are absent from `tools/list` and
are refused by `tools/call`.

For OAuth2 callers, `tools/list` reflects Redmine role permissions rather than
the current token's narrower scopes. A role-permitted tool can therefore be
discovered before scope elevation, but `tools/call` still enforces the current
token scopes; tools denied by the user's role remain hidden.

| Capability | Tools | Required Redmine permission |
|---|---|---|
| Identity | `whoami` | None |
| Projects | `list_projects`, `get_project` | `view_project` |
| Issues | `search_issues`, `get_issue` | `view_issues` |
| Wiki pages | `list_wiki_pages`, `get_wiki_page` | `view_wiki_pages` |
| Metadata | `list_enumerations` | None |
| Users | `list_users` | Filtered by Redmine principal visibility |
| Create an issue | `create_issue` | `add_issues`; read-only mode must be disabled |
| Add an issue note | `add_issue_note` | `add_issue_notes`; private notes also require `set_notes_private`; read-only mode must be disabled |

Tool arguments are validated against their declared schemas. The paginated
tools (`list_projects`, `search_issues`, `list_wiki_pages`, and `list_users`)
support `limit` and `offset`, report pagination metadata, and cap each page at
the configured maximum (100 by default, with an absolute maximum of 1000).

## Prompts

The server also exposes user-invoked prompts through `prompts/list` and
`prompts/get`. A prompt renders instruction text the model then carries out with
the read tools above; the prompt itself reads no Redmine records, so prompts are
offered to every authenticated user and cannot widen what the caller may see.

| Prompt | Purpose |
|---|---|
| `generate_changelog` | Produce an Athena-style changelog for the visible issues of one project version filtered by a single tracker. Takes a single optional `request` argument: free text describing the desired changelog (which version, optional tracker, optional format notes). It may be omitted; the skill then asks what you want and resolves scope interactively through the read tools, defaulting to the house Athena format. |
| `qa_ticket_history_report` | Produce a scoped QA ticket-history report with São Paulo business-hour ownership, retest counting, and Dev/QA identification. Takes one optional `request`: free text naming a project/category/version and/or period, plus any format or calendar overrides. It may be omitted; the skill asks only for missing or ambiguous scope, proposes returned/reproved statuses from the real catalog for confirmation, and then uses the read tools. Weekends are excluded, holidays are not accounted for, and an open issue's ongoing owner interval is excluded from totals. |

Both prompts take a single free-text argument. The server offers no prompt-argument
completion capability. Request text is represented losslessly as inert data and is
never dereferenced, so a long body, path, URL, or delimiter-like text in your notes
is accepted rather than refused. The skills are read-only, and every read tool they
name independently enforces the caller's permissions and record visibility.

## Resources (issue attachments)

The server declares the `resources` capability for one thing: the bytes of a file
attached to a visible issue. It is application- or user-selected context, not a
model-driven tool. `resources/list` is empty and `resources/templates/list`
publishes a single template:

```
redmine://issues/{issue_id}/attachments/{attachment_id}
```

Call `get_issue` with `include_attachments: true` to discover concrete
attachments: each is returned as metadata (including its `resource_uri` and a
credential-free `human_download_url`) and as a `resource_link` content block a
resource-aware client can select. Fetch the bytes with `resources/read` on the
`resource_uri`. The read runs as the authenticated user and rechecks issue and
attachment visibility every time, so a URI is not a capability.

Safe UTF-8 text is returned as `text`; every other type, including HTML and SVG,
is returned as a base64 `blob`. One read is capped at 5 MiB; a larger but visible
attachment is refused with a pointer to its `human_download_url`, which a user
already signed in to Redmine can open in a browser. The capability offers no
subscriptions or change notifications. OAuth callers need the `view_issues` scope
and are challenged to elevate to it when a narrower token is presented.

## Protocol behavior

The server accepts and advertises MCP revisions `2026-07-28`, `2025-11-25`, and
`2025-06-18`. Clients using the newest revision use the stateless
`server/discover` flow; compatibility clients use the `initialize` handshake
with either older revision.

The transport returns one JSON response per authenticated `POST /mcp`. It does not
provide SSE, server-to-client streams, transport sessions, or JSON-RPC batching.
After the endpoint's shared security gates pass, `GET /mcp` and `DELETE /mcp`
return 405. Non-browser clients normally omit `Origin`; every supplied Origin
must match the Redmine base URL or an additional origin configured by an
administrator.

## Development

This repository must be developed and tested as `plugins/redmine_mcp_plugin`
inside a compatible Redmine checkout. Run Rails, Rake, Bundler, migration, and
test commands from the Redmine root:

```sh
bundle install
bin/rails redmine:plugins:migrate NAME=redmine_mcp_plugin RAILS_ENV=development
bin/rails redmine:plugins:test NAME=redmine_mcp_plugin RAILS_ENV=test
RAILS_ENV=test bin/rails test plugins/redmine_mcp_plugin/test/unit/mcp_server_test.rb
```

See the [coding agent guide](AGENTS.md) for repository conventions and the
[architecture document](ARCHITECTURE.md) before changing protocol or
security boundaries. Redmine's official [plugin development
tutorial](https://www.redmine.org/projects/redmine/wiki/Plugin_Tutorial) is useful
background, but its examples target older Redmine versions; this repository's
current behavior, tests, and supported Redmine APIs take precedence.

## License

This plugin is distributed under the GNU General Public License version 2 or
later. See [LICENSE](LICENSE).
