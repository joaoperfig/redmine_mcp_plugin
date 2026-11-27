# frozen_string_literal: true

module RedmineMcpPlugin
  module Prompts
    # Built-in metadata and default text for the seeded `generate_changelog`
    # prompt, which produces an Athena-style changelog for the visible issues of
    # one Redmine project version filtered by a single tracker. The live prompt is
    # built from the stored record by `Prompts.build`; this class is not mounted
    # directly. It exists so a fresh install, and an upgrade that carries saved
    # settings text forward, start from the original skill.
    class GenerateChangelog < Base
      prompt_name 'generate_changelog'
      title 'Generate changelog'
      description 'Produce an Athena-style changelog for the visible issues of a ' \
                  'Redmine project version, resolving scope interactively through ' \
                  'the read tools.'
      arguments [
        MCP::Prompt::Argument.new(
          name: 'request', required: false,
          description: 'Optional plain-language description of the desired ' \
                       'changelog: which version, optional tracker, optional ' \
                       'format notes. May be omitted entirely.'
        )
      ]

      # Format contract distilled from the historical changelog examples. Embedded
      # as the baseline so the scratch template file is never read at runtime and
      # the seven historical examples are not injected into every request. The
      # single-quoted heredoc keeps `#{issue_id}` literal -- it is a placeholder
      # the model fills, not Ruby interpolation.
      BASELINE_TEMPLATE = <<~'TEMPLATE'
        {n}) {Plain-language change title}
        Athena Ref.: #{issue_id}

        Primary Audience: {supported audience, otherwise "Not specified"}

        {Outcome-focused summary}

        What's changed:
        {Evidence-grounded points}

        {Optional "Why this matters" / "How it works" / "New features" section}

        What you need to know:
        {Practical impact or required action}
      TEMPLATE

      # Default for the Prompts tab. Defined after BASELINE_TEMPLATE, which it
      # embeds; see Base for the request placeholder.
      DEFAULT_TEXT = <<~TEXT
        You are generating a release changelog for one Redmine project version,
        covering only issues of a single tracker. This message is a complete,
        standing skill: follow it from start to finish, use only the read tools
        named below, and never write to Redmine.

        {{request}}

        RETRIEVAL ORDER (read tools only)
        - Resolve the project with get_project.
        - Resolve the version within that project with list_versions. Version
          names are not globally unique.
        - Confirm the tracker exists in that project.
        - Fetch every matching issue with
          search_issues(project:, fixed_version_id:, tracker:), using the exact
          fixed_version_id and tracker filters and following pagination to
          completion. Never silently truncate the result.
        - Include an issue only when its tracker field exactly equals the selected
          tracker.
        - Fetch full detail with get_issue for each issue before drafting, so every
          statement is grounded in issue evidence.
        - If nothing matches, return a plain statement that this version and tracker
          have no visible issues. Do not invent entries.

        SCOPE RESOLUTION (ask only for what is missing or ambiguous)
        - Ask every question in natural language in the chat. Never reject the
          invocation.
        - Version is the hard anchor. If you cannot resolve a single version, ask
          the user which version they mean.
        - Project is derived from the version. Ask which project only when the
          version name matches more than one visible project.
        - Ask for the tracker only when it is missing or ambiguous. Never silently
          default to all trackers.
        - When the request already resolves project, version, and tracker
          unambiguously, proceed straight to generation with no confirmation step.

        WRITING RULES
        - Group all entries under the selected tracker, sorted by issue id ascending,
          numbered from 1.
        - Write concise American English for a non-technical, company-wide audience.
        - Render "Athena Ref.: #<issue id>" exactly, using the real issue id. This
          reference line is fixed and cannot be changed by the request.
        - Derive audience, claims, defaults, and required actions only from issue
          evidence. Use "Not specified" rather than inventing missing detail.
        - Keep each entry focused on the user-visible outcome and what the reader
          needs to know.

        PRESENTATION
        - Default to the embedded baseline format below. If the request describes a
          different format in natural language, honor it for presentation only; the
          Athena reference line and all retrieval, scope, evidence, and safety rules
          above stay fixed and cannot be overridden by the request.

        <baseline-format>
        #{BASELINE_TEMPLATE}
        </baseline-format>
      TEXT
    end
  end
end
