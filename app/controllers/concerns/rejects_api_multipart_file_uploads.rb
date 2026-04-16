# frozen_string_literal: true

module RejectsApiMultipartFileUploads
  extend ActiveSupport::Concern

  PRESIGNED_UPLOAD_GUIDANCE = "Use the presigned upload flow instead: POST /v2/files/presign to obtain an upload URL, " \
                              "upload the file directly to that URL, then POST /v2/files/complete. Pass the resulting " \
                              "file URL (for product files) or signed_blob_id (for covers and thumbnails) to this endpoint.".freeze

  included do
    before_action :reject_api_multipart_file_uploads!
  end

  private
    def reject_api_multipart_file_uploads!
      uploaded_keys = request.parameters.each.with_object([]) do |(key, value), acc|
        acc << key.to_s if uploaded_file?(value)
      end
      return if uploaded_keys.empty?

      render_response(
        false,
        message: "Direct multipart file uploads are not supported on this endpoint (received uploaded file in: #{uploaded_keys.to_sentence}). " \
                 "#{PRESIGNED_UPLOAD_GUIDANCE}"
      )
    end

    def uploaded_file?(value)
      value.is_a?(ActionDispatch::Http::UploadedFile) || value.is_a?(Rack::Test::UploadedFile)
    end
end
