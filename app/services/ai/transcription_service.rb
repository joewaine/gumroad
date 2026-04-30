# frozen_string_literal: true

class Ai::TranscriptionService
  class InvalidAudioError < StandardError; end
  class TranscriptionFailedError < StandardError; end

  TRANSCRIPTION_TIMEOUT_IN_SECONDS = 30
  WHISPER_MODEL = "whisper-1"
  MAX_AUDIO_BYTES = 25.megabytes
  MAX_RETRIES = 2
  RETRY_DELAY_IN_SECONDS = 1

  ALLOWED_CONTENT_TYPES = %w[
    audio/webm
    audio/ogg
    audio/wav
    audio/x-wav
    audio/mp4
    audio/m4a
    audio/x-m4a
    audio/mpeg
    audio/mp3
  ].freeze

  def initialize(audio_io:, content_type:, byte_size:, language: nil)
    @audio_io = audio_io
    @content_type = content_type
    @byte_size = byte_size
    @language = language
  end

  def transcribe
    raise InvalidAudioError, "Audio is required" if audio_io.nil? || byte_size.to_i.zero?
    raise InvalidAudioError, "Audio file too large" if byte_size > MAX_AUDIO_BYTES
    raise InvalidAudioError, "Unsupported audio format" unless ALLOWED_CONTENT_TYPES.include?(content_type)

    text, duration = with_retries do
      response = openai_client.audio.transcribe(
        parameters: transcription_parameters
      )

      transcript = response.is_a?(Hash) ? response["text"] : response.to_s
      raise TranscriptionFailedError, "No transcription returned" if transcript.to_s.strip.blank?

      transcript.strip
    end

    { text:, duration_in_seconds: duration }
  end

  private
    attr_reader :audio_io, :content_type, :byte_size, :language

    def transcription_parameters
      params = {
        model: WHISPER_MODEL,
        file: audio_file_for_upload,
      }
      params[:language] = language if language.present?
      params
    end

    def audio_file_for_upload
      tempfile = Tempfile.new(["transcription", extension_for_content_type], binmode: true)
      tempfile.write(audio_io.read)
      tempfile.rewind
      tempfile
    end

    def extension_for_content_type
      case content_type
      when "audio/webm" then ".webm"
      when "audio/ogg" then ".ogg"
      when "audio/wav", "audio/x-wav" then ".wav"
      when "audio/mp4", "audio/m4a", "audio/x-m4a" then ".m4a"
      when "audio/mpeg", "audio/mp3" then ".mp3"
      else ".webm"
      end
    end

    def openai_client
      OpenAI::Client.new(request_timeout: TRANSCRIPTION_TIMEOUT_IN_SECONDS)
    end

    def with_retries
      tries = 0
      start_time = Time.now
      begin
        tries += 1
        result = yield
        duration = Time.now - start_time
        Rails.logger.info("TranscriptionService completed in #{duration.round(2)}s")
        [result, duration]
      rescue InvalidAudioError
        raise
      rescue => e
        if tries < MAX_RETRIES
          Rails.logger.info("TranscriptionService attempt #{tries}/#{MAX_RETRIES} failed: #{e.message}")
          sleep(RETRY_DELAY_IN_SECONDS)
          retry
        else
          duration = Time.now - start_time
          Rails.logger.error("TranscriptionService failed after #{MAX_RETRIES} attempts in #{duration.round(2)}s: #{e.message}")
          raise TranscriptionFailedError, e.message
        end
      end
    end
end
