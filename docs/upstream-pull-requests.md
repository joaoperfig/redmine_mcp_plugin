# Upstream pull request integration

All open pull requests in `joaoperfig/redmine_mcp_plugin` as of November 11, 2026
are included in this fork. Upstream `main` at `2375a2d` was merged first to provide
the current MCP SDK, OAuth, resource, and prompt implementation.

| Pull request | Head commit | Integration |
|---|---|---|
| [#2: Issue updates](https://github.com/joaoperfig/redmine_mcp_plugin/pull/2) | `4544c66` | Already present; ported to the SDK base and retained group assignment. |
| [#3: Time entries](https://github.com/joaoperfig/redmine_mcp_plugin/pull/3) | `1337e87` | Merged; tools ported to the SDK, with own-entry editing permitted by either core edit permission. |
| [#4: Issue attributes and relations](https://github.com/joaoperfig/redmine_mcp_plugin/pull/4) | `cef2fdb` | Merged; combined with fork updates and custom fields. Existing opt-in `get_issue.include_relations` and its response format are retained. |
| [#5: CI and test fixes](https://github.com/joaoperfig/redmine_mcp_plugin/pull/5) | `c274f17` | Merged; controller tests and malformed-JSON handling use the current SDK behavior. |
| [#6: Native search filters](https://github.com/joaoperfig/redmine_mcp_plugin/pull/6) | `26fd5fa` | Merged; SDK schema validation replaces the removed custom validator. Existing top-level filters and sorting are retained. Default status becomes all. |
| [#9: Rails 7.2 migration](https://github.com/joaoperfig/redmine_mcp_plugin/pull/9) | `7a86e40` | Merged unchanged. |
| [#11: Custom fields](https://github.com/joaoperfig/redmine_mcp_plugin/pull/11) | `1c1d6ee` | Merged; issue creation supports custom fields together with status, category, version, parent, and group assignment. |

New write operations retain the discovery, controller, and execution read-only
gates. Their permissions are declared in the OAuth scope-tier map. Parent changes
and private update notes declare their additional permissions before dispatch so
scope challenges cover the whole operation.

## Validation

Validated in an isolated Redmine 6.1 host checkout using Rails 7.2.4, Ruby 3.4.11,
and a dedicated SQLite database:

```sh
RAILS_ENV=test bundle exec rake db:create db:migrate redmine:plugins:migrate
RAILS_ENV=test bundle exec ruby bin/rails test plugins/redmine_mcp_plugin/test
```

The plugin migration succeeded. The complete suite passed with 228 tests,
967 assertions, no failures, no errors, and no skips. All 63 Ruby files passed
syntax checks, `git diff --check` passed, and Git ancestry checks confirmed that
all seven pull request heads are included.

The GitHub Actions matrix from PR #5 also covers Redmine 7.0; that matrix was
not run locally. Deployment requires installing the updated bundle, running the
plugin migration in the deployment environment, and restarting Redmine.
