# frozen_string_literal: true

require "spec_helper"

RSpec.describe BuyerTasteProfileService do
  let(:buyer) { create(:user) }
  let(:music) { Taxonomy.find_or_create_by!(slug: "music-and-sound-design") }
  let(:design) { Taxonomy.find_or_create_by!(slug: "design") }
  let(:writing) { Taxonomy.find_or_create_by!(slug: "writing-and-publishing") }

  describe "#dominant_taxonomy" do
    it "returns the taxonomy the buyer has purchased from most" do
      buy_product_in(music)
      buy_product_in(music)
      buy_product_in(design)

      expect(described_class.new(buyer).dominant_taxonomy).to eq(music)
    end

    it "returns nil when the buyer has no purchases" do
      expect(described_class.new(buyer).dominant_taxonomy).to be_nil
    end

    it "ignores products without a taxonomy" do
      product_without_taxonomy = create(:product, taxonomy: nil)
      create(:purchase, purchaser: buyer, link: product_without_taxonomy)

      expect(described_class.new(buyer).dominant_taxonomy).to be_nil
    end
  end

  describe "#unexplored_top_level_taxonomies" do
    it "excludes top-level taxonomies the buyer has already purchased from" do
      buy_product_in(music)

      result = described_class.new(buyer).unexplored_top_level_taxonomies
      expect(result).not_to include(music)
    end

    it "excludes top-level taxonomies the buyer has already declared interest in" do
      buyer.user_interests.create!(taxonomy: design)

      result = described_class.new(buyer).unexplored_top_level_taxonomies
      expect(result).not_to include(design)
    end

    it "returns at most the requested limit" do
      result = described_class.new(buyer).unexplored_top_level_taxonomies(limit: 2)
      expect(result.size).to be <= 2
    end
  end

  def buy_product_in(taxonomy)
    product = create(:product, taxonomy:)
    create(:purchase, purchaser: buyer, link: product)
  end
end
