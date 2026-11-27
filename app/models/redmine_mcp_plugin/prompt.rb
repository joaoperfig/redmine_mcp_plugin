# frozen_string_literal: true

module RedmineMcpPlugin
  # A user-invoked prompt stored in the host database. `machine_name` is the
  # identifier MCP clients pass to prompts/get and is therefore globally unique;
  # `name`, `description`, and `prompt` are the administrator-editable text. A
  # prompt only renders instructions and reads no Redmine records itself, so it
  # is offered to every authenticated user.
  class Prompt < ApplicationRecord
    self.table_name = 'redmine_mcp_prompts'

    MACHINE_NAME_FORMAT = /\A[a-z0-9_]+\z/

    validates :name, presence: true
    validates :machine_name, presence: true, uniqueness: true,
                             format: { with: MACHINE_NAME_FORMAT }
    validates :prompt, presence: true

    scope :sorted, -> { order(:id) }
  end
end
