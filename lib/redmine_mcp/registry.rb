# frozen_string_literal: true

module RedmineMcp
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
          Tools::ListStatuses,
          Tools::ListVersions,
          Tools::ListUsers,
          Tools::GetGroup,
          Tools::ListIssueCustomFields,
          Tools::CreateIssue,
          Tools::UpdateIssue,
          Tools::AddIssueRelation,
          Tools::AddIssueNote,
          Tools::CreateVersion,
          Tools::CreateWikiPage,
          Tools::ListTimeEntries,
          Tools::CreateTimeEntry,
          Tools::UpdateTimeEntry,
          Tools::DeleteTimeEntry
        ]
      end
    end
  end
end
