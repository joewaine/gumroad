# frozen_string_literal: true

require "spec_helper"

describe Ai::TranscriptionService do
  let(:audio_bytes) { "fake-audio-bytes" }
  let(:audio_io) { StringIO.new(audio_bytes) }
  let(:byte_size) { audio_bytes.bytesize }
  let(:content_type) { "audio/webm" }
  let(:service) do
    described_class.new(audio_io:, content_type:, byte_size:)
  end

  describe "#transcribe" do
    context "with valid audio" do
      let(:openai_response) { { "text" => "  This product changed my life.  " } }

      before do
        audio_double = double("audio")
        allow(audio_double).to receive(:transcribe).and_return(openai_response)
        allow_any_instance_of(OpenAI::Client).to receive(:audio).and_return(audio_double)
      end

      it "returns the transcribed text trimmed" do
        result = service.transcribe

        expect(result[:text]).to eq("This product changed my life.")
        expect(result[:duration_in_seconds]).to be_a(Numeric)
      end

      it "passes the language hint when provided" do
        audio_double = double("audio")
        expect(audio_double).to receive(:transcribe) do |args|
          expect(args[:parameters][:language]).to eq("fr")
          openai_response
        end
        allow_any_instance_of(OpenAI::Client).to receive(:audio).and_return(audio_double)

        described_class.new(audio_io:, content_type:, byte_size:, language: "fr").transcribe
      end

      it "uses the whisper-1 model" do
        audio_double = double("audio")
        expect(audio_double).to receive(:transcribe) do |args|
          expect(args[:parameters][:model]).to eq("whisper-1")
          openai_response
        end
        allow_any_instance_of(OpenAI::Client).to receive(:audio).and_return(audio_double)

        service.transcribe
      end
    end

    context "with invalid audio" do
      it "raises when audio_io is nil" do
        expect do
          described_class.new(audio_io: nil, content_type:, byte_size:).transcribe
        end.to raise_error(described_class::InvalidAudioError, /Audio is required/)
      end

      it "raises when byte_size is zero" do
        expect do
          described_class.new(audio_io:, content_type:, byte_size: 0).transcribe
        end.to raise_error(described_class::InvalidAudioError, /Audio is required/)
      end

      it "raises when byte_size exceeds the maximum" do
        oversized = described_class::MAX_AUDIO_BYTES + 1
        expect do
          described_class.new(audio_io:, content_type:, byte_size: oversized).transcribe
        end.to raise_error(described_class::InvalidAudioError, /too large/)
      end

      it "raises for unsupported content types" do
        expect do
          described_class.new(audio_io:, content_type: "video/mp4", byte_size:).transcribe
        end.to raise_error(described_class::InvalidAudioError, /Unsupported audio format/)
      end
    end

    context "when OpenAI returns an empty transcript" do
      before do
        audio_double = double("audio")
        allow(audio_double).to receive(:transcribe).and_return("text" => "   ")
        allow_any_instance_of(OpenAI::Client).to receive(:audio).and_return(audio_double)
      end

      it "raises TranscriptionFailedError after retrying" do
        expect(service).to receive(:sleep).with(described_class::RETRY_DELAY_IN_SECONDS).at_least(:once)
        expect { service.transcribe }.to raise_error(described_class::TranscriptionFailedError)
      end
    end

    context "when OpenAI raises an error" do
      before do
        audio_double = double("audio")
        allow(audio_double).to receive(:transcribe).and_raise(StandardError, "API down")
        allow_any_instance_of(OpenAI::Client).to receive(:audio).and_return(audio_double)
      end

      it "retries before failing" do
        expect(service).to receive(:sleep).with(described_class::RETRY_DELAY_IN_SECONDS).at_least(:once)
        expect { service.transcribe }.to raise_error(described_class::TranscriptionFailedError, /API down/)
      end
    end
  end
end
