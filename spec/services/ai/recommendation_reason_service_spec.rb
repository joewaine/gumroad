# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::RecommendationReasonService do
  let(:user) { create(:user) }
  let(:product) { create(:product, name: "Sample Pack Vol 4") }

  def stub_openai_with(reason)
    payload = { "choices" => [{ "message" => { "content" => { reason: reason }.to_json } }] }
    allow_any_instance_of(OpenAI::Client).to receive(:chat).and_return(payload)
  end

  describe ".reason_for" do
    before { Rails.cache.clear }

    it "returns the LLM-generated reason" do
      stub_openai_with("Lo-fi producers love this. You're a lo-fi producer.")

      result = described_class.reason_for(user:, product:, declared_interest_label: "lo-fi")

      expect(result).to eq("Lo-fi producers love this. You're a lo-fi producer.")
    end

    it "truncates reasons that exceed the maximum length" do
      stub_openai_with("a" * 500)

      result = described_class.reason_for(user:, product:)

      expect(result.length).to be <= Ai::RecommendationReasonService::MAX_REASON_LENGTH
    end

    it "falls back to a default sentence when the LLM call fails repeatedly" do
      allow_any_instance_of(OpenAI::Client).to receive(:chat).and_raise("network down")

      result = described_class.reason_for(user:, product:)

      expect(result).to eq(Ai::RecommendationReasonService::FALLBACK_REASON)
    end

    it "falls back when the LLM returns malformed JSON" do
      payload = { "choices" => [{ "message" => { "content" => "not json" } }] }
      allow_any_instance_of(OpenAI::Client).to receive(:chat).and_return(payload)

      result = described_class.reason_for(user:, product:)

      expect(result).to eq(Ai::RecommendationReasonService::FALLBACK_REASON)
    end

    it "caches reasons by (user, product, interest)" do
      stub_openai_with("First reason.")
      first = described_class.reason_for(user:, product:, declared_interest_label: "lo-fi")

      stub_openai_with("Different reason.")
      second = described_class.reason_for(user:, product:, declared_interest_label: "lo-fi")

      expect(first).to eq(second)
    end

    it "regenerates the reason when the declared interest label changes" do
      stub_openai_with("Music people.")
      music_reason = described_class.reason_for(user:, product:, declared_interest_label: "music")

      stub_openai_with("Design people.")
      design_reason = described_class.reason_for(user:, product:, declared_interest_label: "design")

      expect(music_reason).not_to eq(design_reason)
    end
  end
end
