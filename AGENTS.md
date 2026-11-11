# Coding agent guide

This is the canonical repository-wide guidance for coding agents. Read it before
changing the plugin. More specific guidance may add to these rules, but should link
back here instead of copying them. `CLAUDE.md` only imports this file; edit this file
when a repository-wide agent rule changes.

## Repository context

`redmine_mcp_plugin` is an in-process Model Context Protocol server for Redmine. It
adds an HTTP MCP endpoint and uses the host application's authentication,
authorization, models, settings, routes, database, and test fixtures. It is not a
standalone Rails application or an independently bootable gem.

Redmine 6.1 or later is the supported host context; [`init.rb`](init.rb) is the
source of truth for that compatibility floor. The host also supplies Rails, Active
Record, and Doorkeeper. [`PluginGemfile`](PluginGemfile) declares the plugin's
additional dependency and is evaluated as part of the Redmine bundle.

The repository is organized as follows:

- `app/` contains the MCP and OAuth metadata controllers plus the plugin settings
  view.
- `config/` contains host-mounted routes and translations.
- `db/migrate/` contains plugin migrations executed against the Redmine database.
- `lib/redmine_mcp_plugin/` contains authentication, SDK server composition,
  protocol-boundary helpers, settings, and SDK-backed tool implementations.
- `test/` contains unit, functional, and integration tests that use Redmine's test
  application and database.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) describes the current host boundary,
  request flow, and security invariants.
- [`docs/mcp-core.md`](docs/mcp-core.md) gives scoped implementation
  guidance for changes to the MCP core.
- `init.rb` registers the plugin and declares its Redmine compatibility.
- [`README.md`](README.md) is operator- and integrator-facing documentation for
  installation, configuration, supported behavior, and client use.

Generated RDoc/YARD output (`doc/`, `rdoc/`, `.yardoc/`, and `_yardoc/`), coverage
output, test temporary files, bundled dependencies, and packaged gems are ignored
artifacts. Change Ruby source comments or the relevant hand-written documentation
instead of editing or committing generated output.

## Work in a Redmine host checkout

Install this repository at `plugins/redmine_mcp_plugin` inside a compatible Redmine
checkout. Run Bundler, Rails, Rake, migration, and test commands from the **Redmine
root**, not from this plugin directory. In the examples below, the current directory
is the Redmine root:

```sh
bundle install
bin/rails server
bin/rails redmine:plugins:migrate NAME=redmine_mcp_plugin RAILS_ENV=development
bin/rails redmine:plugins:test NAME=redmine_mcp_plugin RAILS_ENV=test
```

Run a focused test through the host test runner, for example:

```sh
RAILS_ENV=test bin/rails test plugins/redmine_mcp_plugin/test/unit/mcp_server_test.rb
```

To reverse all migrations owned by this plugin in a disposable environment, run
the host task explicitly with `VERSION=0`:

```sh
bin/rails redmine:plugins:migrate NAME=redmine_mcp_plugin VERSION=0 RAILS_ENV=test
```

Do not add a plugin-local Rails boot path, database configuration, or standalone
test setup. If no compatible Redmine checkout is available, report that host-backed
tests were not run rather than substituting a plugin-only command.

## Repository-wide conventions

- Follow Zeitwerk naming. Every Ruby file under `lib/` must define the constant
  implied by its path. Redmine's plugin loader adds that directory to the main
  autoloader and eager-loads it in production, so do not add manual `require` calls
  for plugin files to compensate for a naming mismatch. External gems have two
  documented loading exceptions: Bundler eagerly requires `mcp` before Zeitwerk
  loads the `MCP::Tool` subclasses, while `doorkeeper-openid_connect` uses
  `require: false` and is loaded lazily by dynamic client registration to avoid
  early controller binding. Keep both contracts documented in `PluginGemfile`.
- Treat authentication, authorization, OAuth and dynamic client registration,
  Origin checks, input validation, permission and visibility filtering, write
  gating, and migrations as security-sensitive. Preserve deny-by-default behavior,
  add focused tests at the affected public boundary, and record non-obvious security
  reasoning next to the code that enforces it.
- Write user-facing prose, identifiers, and comments in American English unless an
  upstream protocol, Redmine API, or locale requires an exact spelling.
- Use concise native RDoc (`#` prose without YARD tags) for a public module, class,
  or method only when it has a non-obvious contract, reason, invariant, constraint,
  or failure mode.
- Keep all other comments to non-obvious contracts, reasons, invariants,
  constraints, and workarounds. Do not narrate the implementation, restate the
  code, preserve change history, or use comments as section dividers.

## Documentation ownership

Keep each fact in its narrowest authoritative home and link to it elsewhere:

- Change this [`AGENTS.md`](AGENTS.md) for repository-wide coding-agent
  instructions, supported development context, and shared conventions.
- Change [`README.md`](README.md) for operator and MCP-client workflows or public
  capabilities.
- Read [`ARCHITECTURE.md`](ARCHITECTURE.md) before changing component
  boundaries, request flow, authentication, authorization, protocol behavior, or
  tool exposure. Follow [`docs/mcp-core.md`](docs/mcp-core.md) when
  implementing those changes.
- Change [`init.rb`](init.rb), [`PluginGemfile`](PluginGemfile),
  [`db/migrate/`](db/migrate/), settings, protocol constants, and tests when the
  behavior they own changes; then update hand-written documentation that links to
  or summarizes that behavior.
- Keep focused architectural rationale adjacent to the implementation it explains.
  When dedicated architecture documentation exists, use it for cross-component
  request flow and design invariants and link to it instead of expanding this entry
  point.
- Do not add instructions to [`CLAUDE.md`](CLAUDE.md); its only purpose is to import
  this file.

Current repository behavior and tests are authoritative. Supported Redmine APIs and
official Redmine documentation provide host context. If an older tutorial conflicts
with either, do not copy its conventions into this plugin.
