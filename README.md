# redmine_mcp_plugin

A [Model Context Protocol](https://modelcontextprotocol.io) server that runs inside Redmine as a plugin,
so there is no second service to deploy or supervise.

It adds one endpoint, `POST /mcp`, and authenticates it with Redmine's own mechanisms. Every tool runs
as a real Redmine user and is limited by that user's permissions.

Status: 0.1.0, early. Read-only by default. Built and verified against Redmine 7.0.0, Rails 8.1.3.1,
Ruby 3.4.10.

## Testing status

The transport, authentication, visibility filtering and OAuth2 scope narrowing were verified over HTTP
against a live Redmine holding production-scale data. The pure-logic unit tests pass.

The 25 functional tests in `test/functional/` have never been run. They were written against an
instance with no test database configured. No real MCP client has connected yet either; everything so
far was done with `curl`. Treat this as working but unproven, and run the suite before relying on it.

## Why a plugin

Most Redmine MCP servers are standalone processes that talk to the REST API. That is a reasonable
design and there are good ones. The cost is a second thing to run: its own runtime, its own service
unit, its own entry in your configuration management, its own restart on reboot, its own reverse proxy
rule, and a second copy of somebody's credentials.

A plugin has none of those. It starts when Redmine starts and is reachable wherever Redmine is
reachable.

In exchange it must not destabilise Redmine, which is why it has no gem dependencies. Adding a gem to a
plugin forces `bundle install` to re-resolve the host application's entire gem set. A failed resolve
does not degrade the plugin, it stops Redmine booting. The JSON-RPC layer is a few hundred lines and is
vendored here.

## Authentication

Four modes, each switchable in Administration, Plugins, Redmine MCP Server. Nothing is invented: each
is a code path Redmine core already implements.

| Mode | Default | Notes |
|---|---|---|
| OAuth2 | on | Recommended. Per-user access tokens from Redmine's own provider. |
| API key | on | The `X-Redmine-API-Key` header. Identifies the user, but carries their full permissions. |
| HTTP Basic | off | Reusable credentials on every request. Refused for accounts with 2FA active, matching core. |
| Session cookie | off | For clients running in the browser. The only mode exposed to CSRF, so it is Origin checked. |

Every token mode also requires the REST API to be enabled in Administration, Settings, API. That is the
same gate core applies.

### Why OAuth2 is the one to use

Redmine 6.1 and later ship a Doorkeeper OAuth2 provider that registers every Redmine permission name as
an OAuth scope, plus `admin`. A token can therefore be strictly weaker than the user who issued it:

- effective access is role permissions intersected with token scopes
- an administrator acting through a token without the `admin` scope is not an administrator
- tokens are listed and revocable under Administration, Applications

Register an application under Administration, Applications, then send `Authorization: Bearer <token>`.

## The permission model, and one trap

Every tool declares the Redmine permission it needs. Before it runs, two independent checks happen:

1. `User#allowed_to?`, which intersects the user's role permissions with the OAuth token's scopes.
2. Core's `.visible` scopes: `Issue.visible`, `Project.visible`, `Principal.visible` and so on.

Both are required. Neither subsumes the other.

`.visible` is built on `Project.allowed_to_condition`, which calls `role.allowed_to?(permission)` with
no scope argument. So the `.visible` scopes honour roles but are blind to OAuth scopes. Measured on
Redmine 7.0.0, with a token holding `view_project` and `view_wiki_pages` but not `view_issues`:

```
User#allowed_to?(:view_issues)  =>  false     # correct
Issue.visible(user).count       =>  5         # five issues, to a token with no issue scope
```

A server that filters only through `.visible` will leak across scopes. This one checks both.

The reverse is also true: `allowed_to?` alone would return rows from projects the user is not a member
of, so the `.visible` scopes are not redundant either.

## Tools

Read-only unless marked write. Write tools are hidden from `tools/list` and refused by `tools/call`
while read-only mode is on, which is the default.

| Tool | Permission |
|---|---|
| `whoami` | none. Reports the identity, auth mode and granted scopes |
| `list_projects`, `get_project` | `view_project` |
| `search_issues`, `get_issue` | `view_issues` |
| `list_wiki_pages`, `get_wiki_page` | `view_wiki_pages` |
| `list_enumerations` | none. Trackers, statuses, priorities |
| `list_users` | none. Filtered by `Principal.visible` |
| `create_issue` (write) | `add_issues` |
| `add_issue_note` (write) | `add_issue_notes`, plus `set_notes_private` for private notes |

`get_issue` respects per-field custom field visibility and private notes.

`list_users` uses `Principal.visible` rather than `User.all`. Redmine's own user list is admin only, and
each role carries a `users_visibility` of either `all` or `members_of_visible_projects`. On a test
instance the same account saw 1212 users under one role and 13 under another. Enumerating `User.all`
would have handed over the whole directory.

## Protocol support

Three revisions, negotiated per request.

2026-07-28 is the current one. It is stateless: no `initialize` handshake and no `Mcp-Session-Id`.
`server/discover` is implemented, as that revision requires. Results carry `resultType` and server
identity in `_meta`. List results carry `ttlMs` and `cacheScope: private`, because the tool set varies
per caller and a shared cache must not hold it.

2025-11-25 and 2025-06-18 are the handshake revisions most shipped clients still speak. `initialize` is
answered for those.

One JSON response per POST, no SSE. `GET /mcp` returns 405, which the transport allows for a server
with no server to client stream, and which 2026-07-28 removed anyway. JSON-RPC batching is refused
rather than half processed.

The `Origin` header is validated on every request, which the transport requires for DNS rebinding
protection. Non-browser MCP clients send no `Origin` and are unaffected.

## Install

```bash
cd /path/to/redmine
git clone https://github.com/joaoperfig/redmine_mcp_plugin.git plugins/redmine_mcp_plugin
# no bundle install: this plugin has no gem dependencies
# no migrations: it has no tables
sudo systemctl restart redmine    # or however you restart your app server
```

Then go to Administration, Plugins, Redmine MCP Server, Configure, and switch the endpoint on. It is
off until you do.

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

Redmine 6.1 or later, which is the floor for the OAuth2 provider. No gems, no migrations, no assets.

## Licence

GPL-2.0-or-later, matching Redmine. See [LICENSE](LICENSE).
