# frozen_string_literal: true

module RedmineMcpPlugin
  # Enforces the inputSchema each tool declares.
  #
  # The schemas used to be documentation only, and a model cannot detect the
  # difference. search_issues declared `status` as enum [open closed all] but
  # fell through to `else scope.open`, so `status: "Closed"` answered with open
  # issues -- a plausible reply to a question nobody asked, with no error to
  # react to. list_projects declared `minimum: 1` on `limit` and returned a full
  # page for `limit: 0`. Whatever the schema promises a client is now checked
  # here, once, before #perform sees the arguments.
  #
  # Not a JSON Schema implementation: it covers the keywords these tools
  # actually declare, listed in ENFORCED. Adding a keyword to a tool schema
  # without teaching it to this file leaves that keyword unenforced, so keep the
  # two in step.
  module SchemaValidator
    ENFORCED = %w[type enum minimum required additionalProperties].freeze

    # Rails will not round-trip a NUL through a bind parameter -- PostgreSQL
    # rejects it outright, and the exception surfaced as -32603 Internal error,
    # which tells the caller nothing. The other C0 controls are equally never
    # meaningful in an identifier or a search needle. Tab, newline and carriage
    # return are left alone: they are legal inside a wiki page title.
    FORBIDDEN_CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

    module_function

    def validate!(schema, arguments)
      return if schema.blank?

      properties = schema['properties'] || {}
      reject_unknown_keys!(schema, properties, arguments)
      require_present!(schema, arguments)

      arguments.each do |key, value|
        spec = properties[key]
        next if spec.nil? || value.nil?

        check_control_characters!(key, value)
        check_type!(key, spec['type'], value)
        check_enum!(key, spec['enum'], value)
        check_minimum!(key, spec['minimum'], value)
      end
    end

    # Returns arguments with declared scalars converted to real Ruby types.
    #
    # Call this after validate!. The string "false" is truthy in Ruby, so a
    # client that sends `{"assigned_to_me": "false"}` -- which check_type!
    # accepts, because shell-built clients send booleans as strings -- would
    # otherwise have it read as true. That is the same failure as the original
    # status enum bug: a plausible answer to a question nobody asked, with no
    # error to react to.
    #
    # Only unambiguous declarations are converted. A property declared
    # `%w[string integer]`, as the project arguments are, is left exactly as it
    # came in; fetch_project already accepts either.
    def coerce(schema, arguments)
      return arguments if schema.blank?

      properties = schema['properties'] || {}
      arguments.each_with_object({}) do |(key, value), out|
        spec = properties[key]
        out[key] = spec.nil? || value.nil? ? value : coerce_value(Array(spec['type']), value)
      end
    end

    def coerce_value(types, value)
      return value unless types.size == 1

      case types.first
      when 'boolean' then [true, 'true'].include?(value)
      when 'integer' then integerish?(value) ? value.to_i : value
      when 'number'  then numeric?(value) ? to_number(value) : value
      else value
      end
    end

    def reject_unknown_keys!(schema, properties, arguments)
      return unless schema['additionalProperties'] == false

      unexpected = arguments.keys - properties.keys
      return if unexpected.empty?

      raise ToolError, "Unknown argument#{'s' if unexpected.size > 1}: " \
                       "#{unexpected.sort.map(&:inspect).join(', ')}. " \
                       "Accepted: #{properties.keys.sort.join(', ')}"
    end

    def require_present!(schema, arguments)
      missing = Array(schema['required']).reject do |key|
        arguments[key].present? || arguments[key] == false
      end
      return if missing.empty?

      raise ToolError, "Missing required argument#{'s' if missing.size > 1}: #{missing.join(', ')}"
    end

    def check_control_characters!(key, value)
      return unless value.is_a?(String) && value.match?(FORBIDDEN_CONTROL)

      raise ToolError, "#{key} contains a control character that is not allowed"
    end

    # A JSON body already carries real types, but clients built out of shell
    # pipelines and templates routinely send "5" for an integer and "true" for a
    # boolean. Those are accepted; anything genuinely unparseable is not.
    #
    # `type` may be a list, which is how the project arguments state what they
    # have always accepted: an identifier or a numeric id.
    def check_type!(key, type, value)
      return if type.nil?

      candidates = Array(type)
      return if candidates.empty?
      return if candidates.any? { |candidate| type_matches?(candidate, value) }

      raise ToolError, "#{key} must be #{name_types(candidates)}, got #{describe(value)}"
    end

    def type_matches?(type, value)
      case type
      when 'string'  then value.is_a?(String)
      when 'integer' then integerish?(value)
      when 'number'  then numeric?(value)
      when 'boolean' then booleanish?(value)
      else true
      end
    end

    def name_types(types)
      types.map do |type|
        case type
        when 'string'  then 'a string'
        when 'integer' then 'an integer'
        when 'number'  then 'a number'
        when 'boolean' then 'true or false'
        else type.to_s
        end
      end.join(' or ')
    end

    def check_enum!(key, allowed, value)
      return if allowed.blank?
      return if allowed.include?(value)

      # Case is not forgiven on purpose. Quietly accepting "Closed" for "closed"
      # is precisely how the original bug read to a caller: like success.
      raise ToolError, "#{key} must be one of #{allowed.join(', ')}, got #{value.inspect}"
    end

    def check_minimum!(key, minimum, value)
      return if minimum.nil? || !numeric?(value)
      return if to_number(value) >= minimum

      raise ToolError, "#{key} must be at least #{minimum}, got #{value.inspect}"
    end

    def integerish?(value)
      return true if value.is_a?(Integer)

      value.is_a?(String) && value.match?(/\A-?\d+\z/)
    end

    def numeric?(value)
      return true if value.is_a?(Numeric)

      value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/)
    end

    def booleanish?(value)
      [true, false, 'true', 'false'].include?(value)
    end

    def to_number(value)
      value.is_a?(Numeric) ? value : value.to_f
    end

    def describe(value)
      case value
      when Hash  then 'an object'
      when Array then 'an array'
      else value.inspect
      end
    end
  end
end
