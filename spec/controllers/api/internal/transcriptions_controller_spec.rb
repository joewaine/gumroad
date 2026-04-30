# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authentication_required"

describe Api::Internal::TranscriptionsController do
  let(:user) { create(:user) }
  let(:audio_file) { fixture_file_upload("test_voice_review.webm", "audio/webm") }
  let(:valid_params) { { audio: audio_file } }

  describe "POST create" do
    it_behaves_like "authentication required for action", :post, :create do
      let(:request_params) { valid_params }
    end

    context "when user is authenticated" do
      before do
        sign_in user
        $redis.del(RedisKey.transcription_throttle(user.id))
      end

      it "transcribes successfully" do
        service_double = instance_double(Ai::TranscriptionService)
        allow(Ai::TranscriptionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:transcribe).and_return(
          text: "I loved this product.",
          duration_in_seconds: 1.2
        )

        post :create, params: valid_params, format: :json

        expect(response).to be_successful
        expect(response.parsed_body).to eq(
          "success" => true,
          "text" => "I loved this product.",
          "duration_in_seconds" => 1.2
        )
      end

      it "passes the language hint to the service when provided" do
        expect(Ai::TranscriptionService).to receive(:new).with(
          hash_including(language: "fr")
        ).and_call_original
        allow_any_instance_of(Ai::TranscriptionService).to receive(:transcribe).and_return(
          text: "Bonjour", duration_in_seconds: 0.5
        )

        post :create, params: valid_params.merge(language: "fr"), format: :json

        expect(response).to be_successful
      end

      it "ignores blank language hints" do
        expect(Ai::TranscriptionService).to receive(:new).with(
          hash_including(language: nil)
        ).and_call_original
        allow_any_instance_of(Ai::TranscriptionService).to receive(:transcribe).and_return(
          text: "Hello", duration_in_seconds: 0.4
        )

        post :create, params: valid_params.merge(language: ""), format: :json

        expect(response).to be_successful
      end

      it "returns 400 when audio is missing" do
        post :create, params: {}, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to eq("success" => false, "error" => "Audio is required")
      end

      it "returns 422 when service rejects the audio as invalid" do
        allow_any_instance_of(Ai::TranscriptionService).to receive(:transcribe)
          .and_raise(Ai::TranscriptionService::InvalidAudioError, "Audio file too large")

        post :create, params: valid_params, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq("success" => false, "error" => "Audio file too large")
      end

      it "returns 500 with a friendly error when transcription fails" do
        allow_any_instance_of(Ai::TranscriptionService).to receive(:transcribe)
          .and_raise(Ai::TranscriptionService::TranscriptionFailedError, "boom")
        expect(ErrorNotifier).to receive(:notify)

        post :create, params: valid_params, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["error"]).to match(/Couldn't transcribe/)
      end

      it "throttles requests when the per-user limit is exceeded" do
        allow_any_instance_of(Ai::TranscriptionService).to receive(:transcribe).and_return(
          text: "ok", duration_in_seconds: 0.1
        )

        described_class.const_get(:TRANSCRIPTION_REQUESTS_PER_PERIOD).times do
          post :create, params: { audio: fixture_file_upload("test_voice_review.webm", "audio/webm") }, format: :json
          expect(response).to be_successful
        end

        post :create, params: { audio: fixture_file_upload("test_voice_review.webm", "audio/webm") }, format: :json

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body["error"]).to match(/Rate limit exceeded/)
        expect(response.headers["Retry-After"]).to be_present
      end
    end
  end
end
