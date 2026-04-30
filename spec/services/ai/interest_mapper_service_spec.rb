# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ai::InterestMapperService do
  let(:music) { Taxonomy.find_or_create_by!(slug: "music-and-sound-design") }
  let(:design) { Taxonomy.find_or_create_by!(slug: "design") }
  let(:fitness) { Taxonomy.find_or_create_by!(slug: "fitness-and-health") }

  before do
    music
    design
    fitness
  end

  def stub_openai(slugs:)
    payload = { "choices" => [{ "message" => { "content" => { slugs: slugs }.to_json } }] }
    allow_any_instance_of(OpenAI::Client).to receive(:chat).and_return(payload)
  end

  describe ".map" do
    it "returns the matched taxonomies for a single-interest prompt" do
      stub_openai(slugs: ["music-and-sound-design"])

      result = described_class.map("I make beats and I love sample packs")

      expect(result).to eq([music])
    end

    it "returns multiple matched taxonomies for a compound prompt" do
      stub_openai(slugs: ["music-and-sound-design", "design"])

      result = described_class.map("I make album artwork for indie musicians")

      expect(result).to contain_exactly(music, design)
    end

    it "rejects taxonomy slugs that aren't on the allowlist" do
      stub_openai(slugs: ["music-and-sound-design", "imaginary-slug"])

      result = described_class.map("anything")

      expect(result).to eq([music])
    end

    it "returns an empty array when nothing matches" do
      stub_openai(slugs: [])

      result = described_class.map("things that don't fit any category")

      expect(result).to eq([])
    end

    it "raises when the prompt is blank" do
      expect { described_class.map(" ") }.to raise_error(Ai::InterestMapperService::InvalidPromptError)
    end

    it "caps the number of returned taxonomies at MAX_RESULTS" do
      stub_const("Ai::InterestMapperService::MAX_RESULTS", 2)
      stub_openai(slugs: ["music-and-sound-design", "design", "fitness-and-health"])

      result = described_class.map("I do everything")

      expect(result.size).to eq(2)
    end
  end
end
