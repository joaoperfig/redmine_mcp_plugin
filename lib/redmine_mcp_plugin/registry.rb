# frozen_string_literal: true

module RedmineMcpPlugin
  # Explicitly registers exposed tools so a stray file cannot become an
  # authenticated endpoint without a visible registry change.
  module Registry
    class << self
      def all
        [
          Tools::WhoAmI,
          Tools::ListProjects,
          Tools::GetProject,
          Tools::GetIssue,
          Tools::SearchIssues,
          Tools::ListWikiPages,
          Tools::GetWikiPage,
          Tools::ListEnumerations,
          Tools::ListTimeEntryActivities,
          Tools::ListTimeEntryFields,
          Tools::ListStatuses,
          Tools::ListVersions,
          Tools::ListUsers,
          Tools::GetGroup,
          Tools::CreateIssue,
          Tools::AddIssueNote,
          Tools::LogTime,
          Tools::CreateVersion,
          Tools::CreateWikiPage
        ]
      end
    end
  end
end
