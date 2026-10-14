# frozen_string_literal: true

module RedmineMcpPlugin
  module Prompts
    # Base class for exposed prompts, a thin layer over the MCP SDK's
    # `MCP::Prompt`. A prompt renders deterministic instruction text with the
    # caller's argument values substituted as inert data; it performs no Redmine
    # access of its own. The read tools the rendered instructions invoke stay
    # independently authorized, so a prompt cannot widen what its caller may see.
    #
    # Subclasses declare the SDK prompt metadata (`prompt_name`, `title`,
    # `description`, `arguments`) and implement the class method `template`.
    class Base < MCP::Prompt
      class << self
        private

        # A single user-role text message is the whole prompt result: the model
        # reads the instructions and drives the workflow with the read tools.
        def user_text_result(text, description: nil)
          MCP::Prompt::Result.new(
            description: description || description_value,
            messages: [
              MCP::Prompt::Message.new(
                role: 'user',
                content: MCP::Content::Text.new(text)
              )
            ]
          )
        end

        # Returns the raw argument value with surrounding whitespace preserved, or
        # nil when absent or blank. Callers that embed free text keep the exact
        # text so a custom template's formatting survives.
        def optional_string(arguments, key)
          value = arguments[key]
          return if value.nil?

          text = value.to_s
          text.strip.empty? ? nil : text
        end

        # Maps a bad prompt argument to Invalid Params (-32602) rather than the
        # default Internal Error, keeping the descriptive message on the wire. The
        # error class and code come from the SDK so the mapping cannot drift from
        # the SDK's own not-found and missing-argument handling.
        def invalid_params!(message)
          raise MCP::Server::RequestHandlerError.new(
            message, nil,
            error_type: :invalid_params,
            error_code: ::JsonRpcHandler::ErrorCode::INVALID_PARAMS
          )
        end
      end
    end
  end
end
