# frozen_string_literal: true

require 'base64'

module RedmineMcpPlugin
  # Application-controlled MCP resources. The only exposed resource type is an
  # issue attachment's bytes, addressed by the dynamic URI template below. The
  # client or user decides whether an attachment enters context: `get_issue`
  # surfaces attachment metadata and `resource_link` blocks, and the bytes are
  # delivered here through `resources/read`. No attachment bytes are returned by a
  # tool, and the `https://` download URL is a manual fallback, never advertised
  # as a client-fetchable MCP resource.
  #
  # Mirrors Tools' Registry and Prompts: exposure is an explicit surface, kept
  # out of the tool and prompt registries so a resource cannot be mistaken for
  # either.
  module Resources
    # The single dynamic URI template this server publishes. `get_issue` builds
    # the same shape for each attachment's `resource_uri`; the two must agree.
    ATTACHMENT_URI_TEMPLATE = 'redmine://issues/{issue_id}/attachments/{attachment_id}'

    # Concrete instances of the template above. Variables match one or more
    # non-slash characters so only a well-formed pair of ids can parse.
    ATTACHMENT_URI_PATTERN =
      %r{\Aredmine://issues/(?<issue_id>\d+)/attachments/(?<attachment_id>\d+)\z}.freeze

    # Reading any attachment is gated on viewing its issue. The controller offers
    # an OAuth step-up for this fixed permission; the read handler re-checks it
    # per issue so a URI remains a name, not a capability.
    READ_PERMISSION = :view_issues

    # One `resources/read` response is capped at 5 MiB of raw bytes. Fixed for
    # this design rather than an administrator setting, and checked against both
    # stored metadata and the actual file size before any bytes are read. Base64
    # expansion is not counted toward the cap.
    MAX_READ_BYTES = 5 * 1024 * 1024

    # Implementation-defined server error for a visible attachment that exceeds
    # the inline cap. It sits in the reserved server range and is emitted only
    # after authorization, when disclosing the size is already permitted.
    RESOURCE_TOO_LARGE_CODE = -32001

    # Active formats that must never be returned as interpretable text. SVG and
    # (X)HTML can carry script, so they are always delivered as opaque blobs for
    # the client to interpret deliberately.
    ACTIVE_MEDIA_TYPES = %w[text/html application/xhtml+xml image/svg+xml].freeze

    class << self
      # The server enumerates no production attachments: `resources/list` is an
      # empty page so the surface stays constant regardless of how many
      # attachments a Redmine installation holds.
      def all
        []
      end

      # The single template `resources/templates/list` publishes. Concrete,
      # discoverable instances come from the `resource_link` blocks `get_issue`
      # returns, not from enumeration here.
      def templates
        [
          MCP::ResourceTemplate.new(
            uri_template: ATTACHMENT_URI_TEMPLATE,
            name: 'issue_attachment',
            title: 'Issue attachment',
            description: 'Bytes of a file attached to a visible Redmine issue, addressed by ' \
                         'issue id and attachment id. Read through resources/read.'
          )
        ]
      end

      # Reads one attachment's bytes for a `resources/read` request. Returns a
      # full result Hash (one `contents` entry plus the fixed cache hints) or
      # raises. Every unavailable case -- malformed URI, absent, invisible,
      # unreadable, or attached to a different issue -- raises the same
      # `-32602` so existence cannot be inferred. The caller sets `User.current`
      # from the authenticated request, so visibility and permission narrow to
      # that caller (OAuth scopes included); these checks run on every read.
      def read(params, user:)
        uri = param(params, :uri).to_s
        issue_id, attachment_id = parse_uri(uri)
        not_found!(uri) if issue_id.nil?

        issue = Issue.visible(user).find_by(id: issue_id)
        not_found!(uri) if issue.nil?
        not_found!(uri) unless user.allowed_to?(READ_PERMISSION, issue.project)

        attachment = Attachment.find_by(id: attachment_id)
        not_found!(uri) if attachment.nil?
        not_found!(uri) unless attached_to?(attachment, issue)
        not_found!(uri) unless attachment.visible?(user) && attachment.readable?

        enforce_size!(attachment)

        { contents: [contents_for(attachment, uri)], ttlMs: 0, cacheScope: 'private' }
      end

      # Whether the caller's roles alone (ignoring OAuth scope narrowing) could
      # ever grant the read. The controller uses this to decide whether a
      # scope-narrowed OAuth token gets a step-up challenge or falls through to
      # the handler's uniform not-found, so a futile challenge is never issued.
      def role_can_read?(user)
        roles = user.roles.to_a | [user.builtin_role]
        roles.any? { |role| role.allowed_to?(READ_PERMISSION) }
      end

      # A plain https URL a user already authenticated to Redmine can open in a
      # browser. It carries no credential and is never advertised as a
      # client-fetchable MCP resource; it is the manual fallback surfaced in
      # issue metadata and in the too-large error. Built from the administrator's
      # configured host, like Redmine's own mail notifications, because a tool or
      # resource read runs without an HTTP request context.
      def download_url(attachment)
        "#{Setting.protocol}://#{Setting.host_name}/attachments/download/" \
          "#{attachment.id}/#{ERB::Util.url_encode(attachment.filename)}"
      end

      private

      def parse_uri(uri)
        match = ATTACHMENT_URI_PATTERN.match(uri)
        return [nil, nil] unless match

        [match[:issue_id].to_i, match[:attachment_id].to_i]
      end

      # The container must be exactly this issue: an attachment addressed through
      # one issue's URI but owned by another record must not be readable.
      def attached_to?(attachment, issue)
        attachment.container_type == 'Issue' && attachment.container_id == issue.id
      end

      # Checks the stored size first, then the file on disk as a backstop, so a
      # metadata/file mismatch cannot smuggle oversized content past the cap. The
      # cap guards raw bytes, so it runs before any read.
      def enforce_size!(attachment)
        too_large!(attachment) if attachment.filesize.to_i > MAX_READ_BYTES

        path = attachment.diskfile
        too_large!(attachment) if path && File.exist?(path) && File.size(path) > MAX_READ_BYTES
      end

      # Safe UTF-8 text is returned as `text`; everything else is a base64
      # `blob` with the resolved MIME type, falling back to
      # application/octet-stream for an unknown type. Active formats never reach
      # the text branch, and a declared-text file whose bytes are not valid UTF-8
      # degrades to a blob rather than emitting malformed text.
      def contents_for(attachment, uri)
        bytes = File.binread(attachment.diskfile)
        mime = attachment.content_type.presence

        if textual?(mime)
          text = bytes.dup.force_encoding(Encoding::UTF_8)
          return { uri: uri, mimeType: mime, text: text } if text.valid_encoding?
        end

        { uri: uri, mimeType: mime || 'application/octet-stream', blob: Base64.strict_encode64(bytes) }
      end

      def textual?(mime)
        return false if mime.nil?

        normalized = mime.split(';').first.to_s.strip.downcase
        return false if ACTIVE_MEDIA_TYPES.include?(normalized)

        normalized.start_with?('text/') || normalized == 'application/json' || normalized.end_with?('+json')
      end

      def not_found!(uri)
        raise MCP::Server::ResourceNotFoundError.new(uri)
      end

      def too_large!(attachment)
        raise MCP::Server::RequestHandlerError.new(
          "Attachment #{attachment.id} is #{attachment.filesize} bytes, above the " \
          "#{MAX_READ_BYTES}-byte resources/read limit. Download it directly at " \
          "#{download_url(attachment)}.",
          nil,
          error_type: :internal_error,
          error_code: RESOURCE_TOO_LARGE_CODE
        )
      end

      # Transports symbolize keys, but a direct caller (tests, other plugins) may
      # pass string keys, so both are tolerated.
      def param(params, key)
        return unless params.is_a?(Hash)

        value = params[key.to_sym]
        value.nil? ? params[key.to_s] : value
      end
    end
  end
end
