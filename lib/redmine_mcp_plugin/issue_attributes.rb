# frozen_string_literal: true

module RedmineMcpPlugin
  # Name-to-id resolution shared by create_issue and update_issue, for the
  # fields a caller names rather than numbers.
  #
  # The resolvers take the issue, not just its project, because what is
  # assignable depends on it: versions on the project and its sharing settings,
  # statuses on the workflow.
  #
  # "none" clears an optional field, the convention assigned_to already uses.
  module IssueAttributes
    # Fields safe_attributes= may drop without a word. See ensure_applied!.
    CHECKED_ATTRIBUTES = %w[status_id category_id fixed_version_id parent_issue_id].freeze

    private

    def none?(value)
      value.to_s.strip.casecmp('none').zero?
    end

    def status_id_for(issue, name)
      status = IssueStatus.find_by(name: name.to_s)
      raise ToolError, "Project #{issue.project.identifier} has no status named #{name.to_s.inspect}" if status.nil?

      status.id
    end

    def category_id_for(issue, name)
      return nil if none?(name)

      category = issue.project.issue_categories.find_by(name: name.to_s)
      raise ToolError, "Project #{issue.project.identifier} has no category named #{name.to_s.inspect}" if category.nil?

      category.id
    end

    # assignable_versions rather than project.versions: it applies version
    # sharing and leaves out closed and locked versions, which is exactly what
    # the issue form offers.
    def fixed_version_id_for(issue, name)
      return nil if none?(name)

      version = issue.assignable_versions.detect { |candidate| candidate.name == name.to_s }
      if version.nil?
        raise ToolError, "No open version named #{name.to_s.inspect} is available in #{issue.project.identifier}"
      end

      version.id
    end

    # parent_issue_id is a safe attribute only with :manage_subtasks. Checked
    # up front so a caller without it is told, not ignored. The parent goes
    # through Issue.visible like every other issue lookup; core then validates
    # cross-project subtask settings and cycles on save.
    def parent_issue_id_for(issue, value)
      authorize!(:manage_subtasks, issue.project)
      return nil if none?(value)

      # "#5" as well as 5, like the parent field in the issue form.
      parent = Issue.visible(user).find_by(id: value.to_s.delete_prefix('#').to_i)
      raise ToolError, "No visible issue with id #{value.inspect}" if parent.nil?

      parent.id
    end

    # safe_attributes= filters by permission and by workflow -- read-only
    # fields, disallowed status transitions -- and drops what it filters
    # silently. Without this check a status that did not stick comes back as
    # success, which is the plausible-answer-to-another-question failure
    # SchemaValidator exists to prevent.
    def ensure_applied!(issue, attributes)
      ignored = attributes.slice(*CHECKED_ATTRIBUTES).reject { |key, value| issue.public_send(key) == value }.keys
      return if ignored.empty?

      raise ToolError, "Not allowed to set #{ignored.join(', ')} on this issue"
    end
  end
end
