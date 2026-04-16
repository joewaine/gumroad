# frozen_string_literal: true

module RejectsApiMultipartFileUploads
  extend ActiveSupport::Concern

  PRESIGNED_UPLOAD_GUIDANCE = "Use the presigned upload flow: POST /v2/files/presign to obtain an upload URL, " \
                              "upload the file directly to that URL, then pass the resulting URL to this endpoint."

  included do
    before_action :reject_api_multipart_file_uploads!, if: -> { doorkeeper_token.present? }
  end

  private
    def reject_api_multipart_file_uploads!
      uploaded_keys = find_uploaded_keys(request.parameters)
      return if uploaded_keys.empty?

      message = "Direct multipart file uploads are not supported on this endpoint " \
                "(received uploaded file at: #{uploaded_keys.to_sentence}). " \
                "#{PRESIGNED_UPLOAD_GUIDANCE}"
      render status: :bad_request, json: { success: false, message: }
    end

    def find_uploaded_keys(value, path = [])
      case value
      when ActionController::Parameters, Hash
        value.flat_map { |k, v| find_uploaded_keys(v, path + [k.to_s]) }
      when Array
        value.each_with_index.flat_map { |v, i| find_uploaded_keys(v, path + [i.to_s]) }
      else
        uploaded_file?(value) ? [path.join(".")] : []
      end
    end

    def uploaded_file?(value)
      value.is_a?(ActionDispatch::Http::UploadedFile) || value.is_a?(Rack::Test::UploadedFile)
    end
end
