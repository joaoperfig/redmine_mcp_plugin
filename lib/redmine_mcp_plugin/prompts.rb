# frozen_string_literal: true

module RedmineMcpPlugin
  # User-invoked prompt templates. A prompt renders instruction text for the model
  # to follow and reads no Redmine records itself, so prompts are exposed to every
  # authenticated user with no per-user discovery gate; the read tools their
  # instructions invoke stay independently authorized. Mirrors Tools' Registry:
  # exposure is an explicit list, so a stray file under prompts/ cannot become an
  # exposed prompt.
  module Prompts
    class << self
      def all
        [
          Prompts::GenerateChangelog,
          Prompts::QaTicketHistoryReport
        ]
      end
    end
  end
end
