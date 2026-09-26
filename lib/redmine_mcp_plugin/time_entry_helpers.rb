# frozen_string_literal: true

module RedmineMcpPlugin
  # Shared by the time entry tools, so that they parse arguments and render
  # entries the same way.
  module TimeEntryHelpers
    private

    # Before authorize!, for the reason given on Tool#fetch_wiki.
    def require_time_tracking!(project)
      return if project.module_enabled?(:time_tracking)

      raise ToolError, "The time tracking module is not enabled for project #{project.identifier}"
    end

    # Only the caller's own entries. Edit and delete share one refusal whether
    # the entry is missing, invisible or somebody else's, so the message does
    # not confirm that an entry exists.
    def fetch_own_time_entry(id)
      time_entry = TimeEntry.visible(user).where(user_id: user.id).find_by(id: id.to_i)
      raise ToolError, "No time entry of yours with id #{id.inspect}" if time_entry.nil?

      require_time_tracking!(time_entry.project)
      # Core's rule: edit_time_entries covers the caller's own entries too, so a
      # role holding only that permission must still pass. allowed_to? inside
      # it honours OAuth scopes.
      raise ToolError, 'You do not have permission to do that' unless time_entry.editable_by?(user)

      time_entry
    end

    # Attributes for safe_attributes=, taken only from the arguments present.
    def time_entry_attributes(arguments, project)
      attributes = {}
      attributes['hours'] = arguments['hours'].to_s if arguments.key?('hours')
      attributes['comments'] = arguments['comments'].to_s if arguments.key?('comments')

      if (spent_on = arguments['spent_on'].presence)
        begin
          attributes['spent_on'] = Date.iso8601(spent_on.to_s).to_s
        rescue ArgumentError
          raise ToolError, "spent_on must be an ISO-8601 date, got #{spent_on.inspect}"
        end
      end

      if (activity_name = arguments['activity'].presence)
        # project.activities, not TimeEntryActivity.active: a project may
        # disable or override the shared activities.
        activity = project.activities.find_by(name: activity_name.to_s)
        raise ToolError, "Project #{project.identifier} has no active activity named #{activity_name.inspect}" if activity.nil?

        attributes['activity_id'] = activity.id
      end

      attributes
    end

    # hours is a Rational on the model; to_json would render 3 as "3/1".
    def summarise_time_entry(time_entry)
      issue = time_entry.issue
      {
        id: time_entry.id,
        spent_on: time_entry.spent_on&.iso8601,
        hours: time_entry.hours&.to_f,
        project_identifier: time_entry.project&.identifier,
        issue_id: time_entry.issue_id,
        # A time entry can be visible while its issue is not. visible? alone is
        # blind to OAuth scopes -- see the note on Tool.
        issue_subject: issue_readable?(issue) ? issue.subject : nil,
        user: time_entry.user&.name,
        activity: time_entry.activity&.name,
        comments: time_entry.comments,
        created_on: iso(time_entry.created_on),
        updated_on: iso(time_entry.updated_on)
      }
    end

    def issue_readable?(issue)
      issue.present? && issue.visible?(user) && user.allowed_to?(:view_issues, issue.project)
    end
  end
end
