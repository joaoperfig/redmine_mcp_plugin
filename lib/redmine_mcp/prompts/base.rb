# frozen_string_literal: true

module RedmineMcp
  module Prompts
    # Base class for exposed prompts, a thin layer over the MCP SDK's
    # `MCP::Prompt`. A prompt renders deterministic instruction text with the
    # caller's argument values substituted as inert data; it performs no Redmine
    # access of its own. The read tools the rendered instructions invoke stay
    # independently authorized, so a prompt cannot widen what its caller may see.
    #
    # Subclasses declare the SDK prompt metadata (`prompt_name`, `title`,
    # `description`, `arguments`), a `DEFAULT_TEXT`, and the class methods
    # `template` and `request_section`.
    #
    # The text served is the administrator's from the settings page's Prompts
    # tab, falling back to `DEFAULT_TEXT`. `REQUEST_PLACEHOLDER` marks where the
    # rendered request section goes; a text without it gets the section
    # appended, so an edit can never drop the caller's request or the framing
    # that marks it as data rather than instructions.
    class Base < MCP::Prompt
      REQUEST_PLACEHOLDER = '{{request}}'

      class << self
        def setting_key
          "prompt_#{name_value}"
        end

        def instruction_text
          Settings.text(setting_key, self::DEFAULT_TEXT)
        end

        private

        # The block form of sub keeps backslash sequences in the request, such
        # as \1 or \0, literal instead of being read as back-references.
        def render(request:)
          section = request_section(request)
          text = instruction_text
          if text.include?(REQUEST_PLACEHOLDER)
            text.sub(REQUEST_PLACEHOLDER) { section }
          else
            "#{text.rstrip}\n\n#{section}\n"
          end
        end

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
