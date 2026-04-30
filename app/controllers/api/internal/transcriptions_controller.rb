# frozen_string_literal: true

class Api::Internal::TranscriptionsController < Api::Internal::BaseController
  include Throttling

  before_action :authenticate_user!
  before_action :throttle_transcription_requests

  TRANSCRIPTION_REQUESTS_PER_PERIOD = 30
  TRANSCRIPTION_REQUESTS_PERIOD_WINDOW = 1.hour
  private_constant :TRANSCRIPTION_REQUESTS_PER_PERIOD, :TRANSCRIPTION_REQUESTS_PERIOD_WINDOW

  def create
    audio = params[:audio]

    if audio.blank? || !audio.respond_to?(:read)
      render json: { success: false, error: "Audio is required" }, status: :bad_request
      return
    end

    service = ::Ai::TranscriptionService.new(
      audio_io: audio,
      content_type: audio.content_type.to_s,
      byte_size: audio.size,
      language: params[:language].presence
    )

    result = service.transcribe

    render json: {
      success: true,
      text: result[:text],
      duration_in_seconds: result[:duration_in_seconds]
    }
  rescue ::Ai::TranscriptionService::InvalidAudioError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error("Voice transcription failed: #{e.full_message}")
    ErrorNotifier.notify(e)
    render json: { success: false, error: "Couldn't transcribe — please type your message instead." }, status: :internal_server_error
  end

  private
    def throttle_transcription_requests
      return unless current_user

      key = RedisKey.transcription_throttle(current_user.id)
      throttle!(key:, limit: TRANSCRIPTION_REQUESTS_PER_PERIOD, period: TRANSCRIPTION_REQUESTS_PERIOD_WINDOW)
    end
end
