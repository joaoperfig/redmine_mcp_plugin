# CLAUDE.md — redmine_mcp_plugin

## What this is

A Model Context Protocol server that runs **inside Redmine as a plugin**. One endpoint, `POST /mcp`,
authenticated with Redmine's own mechanisms. GPL-2.0, matching Redmine.

Written 2026-08-28. Developed against **Redmine 7.0.0.stable / Rails 8.1.3.1 / Ruby 3.4.10**.

## Three constraints that are not negotiable

1. ⛔ **No gem dependencies. Ever.** Adding a gem to a Redmine plugin forces `bundle install` to
   re-resolve the *host application's* entire gem set. A failed resolve does not degrade this plugin —
   it stops Redmine booting. The JSON-RPC layer is vendored for exactly this reason. If a feature seems
   to need a gem, it does not go in.
2. ⛔ **No migrations, no assets.** Both add upgrade and deployment steps to somebody's production
   Redmine. The plugin has no tables and no precompiled files, so installing it is a clone and a restart.
3. ⛔ **Never invent a credential mechanism.** Every authentication branch in `Authenticator` mirrors a
   path core's `ApplicationController#find_current_user` already takes. The plugin's contribution is
   making each one switchable — not adding a fifth.

## The permission model, and why it checks twice

Every tool declares a Redmine permission. Before it runs, **both** of these happen:

1. `User#allowed_to?` — intersects role permissions with the OAuth token's scopes.
2. Core's `.visible` scopes — `Issue.visible`, `Project.visible`, `Principal.visible`.

⛔ **Neither subsumes the other, and deleting either one is a security regression.**

`Project.allowed_to_condition` (`project.rb:189`) calls `role.allowed_to?(permission)` with **no scope
argument**. So `.visible` honours roles and is **blind to OAuth scopes**. Measured on 7.0.0, one token
holding `view_project` + `view_wiki_pages` but not `view_issues`:

```
User#allowed_to?(:view_issues)  =>  false
Issue.visible(user).count       =>  5      # would have leaked
```

Conversely `allowed_to?` alone returns rows from projects the user is not a member of. Both. Always.

## Core traps found the hard way — do not rediscover these

- ⛔ **`User` declares `attr_writer :oauth_scope` with no reader** (`user.rb:122`). `user.oauth_scope`
  raises `NoMethodError`. Scopes are carried in the plugin's own `auth` context, set by `Authenticator`.
- ⛔ **`Issue#private_notes=` delegates to `current_journal` with `allow_nil: true`** (`issue.rb:70`).
  Setting it **before** `init_journal` is silently swallowed and the note ships **public**.
- ⛔ **Zeitwerk eager-loads `plugins/*/lib`** (`plugin_loader.rb:81`,
  `paths.add 'lib', eager_load: true`). **One class per file, filename matching the constant.** A file
  with two classes is a hard boot failure. Never add a manual `require` under `lib/`.
- ⛔ **Plugin settings arrive with SYMBOL keys until an admin saves the form once** — Redmine hands back
  `init.rb`'s defaults hash verbatim. Always read through `RedmineMcpPlugin::Settings`, which wraps
  `with_indifferent_access`. The settings partial does the same, for the same reason.
- ⚠ **Doorkeeper has `hash_token_secrets` on.** `AccessToken#token` is a hash. `plaintext_token` is what
  a client sends, and it exists **only** on the newly created object.
- ⚠ **`allow_token_introspection` is false.** RFC 7662 introspection does not work against a stock
  Redmine 7.

## Conventions

- **Refusals must not leak existence.** An invisible record and a nonexistent one get the *same* wording.
  An unavailable tool and an unknown tool are both "Unknown tool". This is deliberate — do not "improve"
  the error messages.
- **Write tools declare `write: true`** and are hidden and refused while read-only mode is on, which is
  the default.
- **Never assign attributes in bulk from client input.** Use `Issue#safe_attributes=`, which is core's
  per-user, per-workflow field filter. `assign_attributes` would let a caller set `author_id`.
- **Registry is an explicit list, not a `Dir.glob`.** Adding a tool should be a visible act in the diff.
- **The internal-error branch does not echo the exception message** — it can carry SQL, paths or record
  contents.

## Protocol

Three revisions, negotiated per request. **2026-07-28 removed the `initialize` handshake and
`Mcp-Session-Id`** — MCP is stateless now, which is why it fits a Rails controller. `server/discover` is
required by that revision and is implemented; `initialize` is still answered for 2025-06-18 /
2025-11-25, which is what shipped clients speak.

Single JSON response per POST, no SSE. `GET` → 405. Batching refused. `Origin` validated on every
request (a transport MUST); non-browser clients send none and are unaffected.

## Testing

```bash
# Pure logic, no Rails needed — these pass.
# Rails suite, from the Redmine root:
bin/rails redmine:plugins:test NAME=redmine_mcp_plugin RAILS_ENV=test
```

⛔ **`test/functional/mcp_controller_test.rb` (25 tests) has never been executed.** It was written
against a Redmine whose `database.yml` had no `test:` section. **Do not describe it as passing** until
someone runs it.

## Style

Match the surrounding code: frozen string literals, `# frozen_string_literal: true`, Redmine's two-space
indentation, and comments that explain *why* rather than *what* — particularly where the reason is a
core behaviour that is not obvious from reading this file.
