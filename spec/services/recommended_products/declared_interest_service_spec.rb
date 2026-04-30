# frozen_string_literal: true

require "spec_helper"

RSpec.describe RecommendedProducts::DeclaredInterestService do
  let(:user) { create(:user) }
  let(:taxonomy) { create(:taxonomy, slug: "declared-interest-test") }

  describe ".fetch" do
    context "without a user" do
      it "returns an empty array" do
        expect(described_class.fetch(user: nil, taxonomy:)).to eq([])
      end
    end

    context "without a taxonomy" do
      it "returns an empty array" do
        expect(described_class.fetch(user:, taxonomy: nil)).to eq([])
      end
    end

    context "when the user has no purchases" do
      it "falls back to popular products in the declared taxonomy" do
        in_taxonomy = create(:product, taxonomy:)
        elsewhere = create(:product)

        result = described_class.fetch(user:, taxonomy:)

        expect(result).to include(in_taxonomy)
        expect(result).not_to include(elsewhere)
      end

      it "excludes archived products from the fallback" do
        archived = create(:product, taxonomy:, archived: true)
        live = create(:product, taxonomy:)

        result = described_class.fetch(user:, taxonomy:)

        expect(result).to include(live)
        expect(result).not_to include(archived)
      end

      it "excludes adult products from the fallback" do
        adult = create(:product, taxonomy:, is_adult: true)
        safe = create(:product, taxonomy:)

        result = described_class.fetch(user:, taxonomy:)

        expect(result).to include(safe)
        expect(result).not_to include(adult)
      end
    end

    context "when the user has purchases that bridge to products in the declared taxonomy" do
      let(:purchased) { create(:product) }
      let(:bridged) { create(:product, taxonomy:) }
      let(:non_bridged_in_taxonomy) { create(:product, taxonomy:) }

      before do
        create(:purchase, purchaser: user, link: purchased)
        allow(SalesRelatedProductsInfo).to receive(:related_products)
          .and_return(Link.where(id: [bridged.id, non_bridged_in_taxonomy.id]))
      end

      it "includes bridged products from the declared taxonomy" do
        result = described_class.fetch(user:, taxonomy:)
        expect(result).to include(bridged)
      end

      it "excludes products the user has already purchased" do
        result = described_class.fetch(user:, taxonomy:)
        expect(result).not_to include(purchased)
      end
    end

    context "when there are fewer bridged products than the requested limit" do
      let!(:purchased) { create(:product) }
      let!(:bridged) { create(:product, taxonomy:) }
      let!(:popular_filler) { create(:product, taxonomy:) }

      before do
        create(:purchase, purchaser: user, link: purchased)
        allow(SalesRelatedProductsInfo).to receive(:related_products)
          .and_return(Link.where(id: [bridged.id]))
      end

      it "tops up with popular products in the same taxonomy" do
        result = described_class.fetch(user:, taxonomy:, limit: 2)
        expect(result).to include(bridged)
        expect(result).to include(popular_filler)
      end
    end

    it "respects the limit argument" do
      create_list(:product, 5, taxonomy:)

      result = described_class.fetch(user:, taxonomy:, limit: 3)
      expect(result.size).to eq(3)
    end
  end
end
