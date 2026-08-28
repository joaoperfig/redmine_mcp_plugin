# frozen_string_literal: true

module RedmineMcpPlugin
  # The set of tools this server exposes.
  #
  # Explicit list, not a Dir.glob over the tools directory. A glob means a stray
  # file dropped into plugins/redmine_mcp_plugin/lib/.../tools/ becomes a live,
  # authenticated endpoint; requiring an edit here makes adding a tool a visible
  # act in the diff.
  module Registry
    class << self
      def all
        [
          Tools::WhoAmI,
          Tools::ListProjects,
          Tools::GetProject,
          Tools::SearchIssues,
          Tools::GetIssue,
          Tools::ListWikiPages,
          Tools::GetWikiPage,
          Tools::ListEnumerations,
          Tools::ListUsers,
          Tools::CreateIssue,
          Tools::AddIssueNote
        ]
      end

      # Tools this user may see. tools/list is permitted to vary by the
      # authorization on the request; the 2026-07-28 spec says so explicitly,
      # and it means a scope-narrowed token is not shown tools it cannot call.
      def visible_to(user)
        all.select { |tool| tool.available_to?(user) }
      end

      def find(name, user)
        visible_to(user).detect { |tool| tool.mcp_name == name.to_s }
      end
    end
  end
end
