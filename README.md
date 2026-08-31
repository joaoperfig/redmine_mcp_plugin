# redmine_mcp_plugin

A [Model Context Protocol](https://modelcontextprotocol.io) server that runs inside Redmine as a
plugin. It adds one endpoint, `POST /mcp`, and authenticates it with Redmine's own mechanisms. Every
tool runs as a real Redmine user and is limited by that user's permissions.

Version 0.1.0. Read-only by default. Built against Redmine 7.0.0, Rails 8.1.3.1, Ruby 3.4.10.

## Status

The transport, authentication, visibility filtering and OAuth2 scope narrowing were verified over HTTP
against a live Redmine holding production-scale data. The pure-logic unit tests pass.

The 25 functional tests in `test/functional/` have never been run, and neither have the
`SchemaValidator` unit tests added alongside them. No MCP client has connected yet; everything so far
was done with `curl` and scripts. Run the suite before relying on it.

## Install

```bash
cd /path/to/redmine
git clone https://github.com/joaoperfig/redmine_mcp_plugin.git plugins/redmine_mcp_plugin
sudo systemctl restart redmine    # or however you restart your app server
```

No `bundle install`, no migrations. Then go to Administration, Plugins, Redmine MCP Server, Configure
and switch the endpoint on. It is off until you do.

## Authentication

Four modes, each switchable in Administration, Plugins, Redmine MCP Server. Each is a code path
Redmine core already implements.

| Mode | Default | Notes |
|---|---|---|
| OAuth2 | on | Per-user access tokens from Redmine's own provider. Scopes can narrow a token below the issuing user's own permissions. |
| API key | on | The `X-Redmine-API-Key` header. Carries the user's full permissions. |
| HTTP Basic | off | Reusable credentials on every request. Refused for accounts with 2FA active, matching core. |
| Session cookie | off | For clients running in the browser. Origin checked. |

Every token mode also requires the REST API to be enabled in Administration, Settings, API.

For OAuth2, register an application under Administration, Applications, then send
`Authorization: Bearer <token>`.

### Discovery

Two documents let a client find the authorization server without being told where it is:

```
/.well-known/oauth-protected-resource        RFC 9728
/.well-known/oauth-protected-resource/mcp
/.well-known/oauth-authorization-server      RFC 8414
```

A 401 from `/mcp` carries `WWW-Authenticate: Bearer realm="Redmine", resource_metadata="..."` pointing
at the first of those. Both are served only while the endpoint and OAuth2 mode are enabled.

Redmine has no dynamic client registration (RFC 7591), so no `registration_endpoint` is advertised.
Create the application by hand and give the client its id and secret.

## Permission model

Every tool declares the Redmine permission it needs. Two checks run before it does:

1. `User#allowed_to?`, which intersects the user's role permissions with the OAuth token's scopes.
2. Core's `.visible` scopes: `Issue.visible`, `Project.visible`, `Principal.visible` and so on.

Both are needed. `.visible` is built on `Project.allowed_to_condition`, which calls
`role.allowed_to?(permission)` with no scope argument, so it honours roles but is blind to OAuth
scopes. Measured on Redmine 7.0.0, with a token holding `view_project` and `view_wiki_pages` but not
`view_issues`:

```
User#allowed_to?(:view_issues)  =>  false
Issue.visible(user).count       =>  5
```

`allowed_to?` alone would return rows from projects the user is not a member of, so neither check is
redundant.

## Tools

Read-only unless marked write. Write tools are hidden from `tools/list` and refused by `tools/call`
while read-only mode is on, which is the default.

| Tool | Permission |
|---|---|
| `whoami` | none. Reports identity, auth mode and granted scopes |
| `list_projects`, `get_project` | `view_project` |
| `search_issues`, `get_issue` | `view_issues` |
| `list_wiki_pages`, `get_wiki_page` | `view_wiki_pages` |
| `list_enumerations` | none. Trackers, statuses, priorities |
| `list_users` | none. Filtered by `Principal.visible` |
| `create_issue` (write) | `add_issues` |
| `add_issue_note` (write) | `add_issue_notes`, plus `set_notes_private` for private notes |

`get_issue` respects per-field custom field visibility and private notes. `list_users` uses
`Principal.visible` rather than `User.all`, which honours each role's `users_visibility` setting.

Arguments are checked against each tool's declared schema. A value outside a declared `enum`, below a
declared `minimum`, of the wrong type, or missing when required is refused rather than ignored.

The list tools take `limit` and `offset` and return `total_count`, `returned`, `offset` and `has_more`.
`limit` is capped by the `max_results` setting, 100 by default, so page with `offset`.

## Protocol

Three revisions, negotiated per request.

2026-07-28 is stateless: no `initialize` handshake and no `Mcp-Session-Id`. `server/discover` is
implemented, as that revision requires. Results carry `resultType` and server identity in `_meta`, and
list results carry `ttlMs` and `cacheScope: private` because the tool set varies per caller.

2025-11-25 and 2025-06-18 are the handshake revisions most shipped clients still speak. `initialize` is
answered for those.

One JSON response per POST, no SSE. `GET /mcp` returns 405. JSON-RPC batching is refused rather than
half processed. The `Origin` header is validated on every request for DNS-rebinding protection;
non-browser clients send none and are unaffected.

## Client configuration

```json
{
  "mcpServers": {
    "redmine": {
      "type": "http",
      "url": "https://redmine.example.com/mcp",
      "headers": { "Authorization": "Bearer YOUR_OAUTH2_TOKEN" }
    }
  }
}
```

In API key mode, use `"headers": { "X-Redmine-API-Key": "YOUR_KEY" }` instead.

## Requirements

Redmine 6.1 or later.

## Licence

GPL-2. See [LICENSE](LICENSE).
