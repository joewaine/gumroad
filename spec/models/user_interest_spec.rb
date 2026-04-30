# frozen_string_literal: true

require "spec_helper"

RSpec.describe UserInterest do
  subject(:user_interest) { build(:user_interest) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:taxonomy) }
  end

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:taxonomy_id) }

    it "allows source_text up to the maximum length" do
      user_interest.source_text = "a" * UserInterest::SOURCE_TEXT_MAX_LENGTH
      expect(user_interest).to be_valid
    end

    it "rejects source_text beyond the maximum length" do
      user_interest.source_text = "a" * (UserInterest::SOURCE_TEXT_MAX_LENGTH + 1)
      expect(user_interest).not_to be_valid
      expect(user_interest.errors[:source_text]).to be_present
    end

    it "permits source_text to be nil" do
      user_interest.source_text = nil
      expect(user_interest).to be_valid
    end
  end

  describe "uniqueness across user and taxonomy" do
    let(:user) { create(:user) }
    let(:taxonomy) { create(:taxonomy) }

    it "prevents duplicate interest records for the same pair" do
      create(:user_interest, user:, taxonomy:)
      duplicate = build(:user_interest, user:, taxonomy:)
      expect(duplicate).not_to be_valid
    end

    it "allows the same taxonomy to be declared by different users" do
      other_user = create(:user)
      create(:user_interest, user:, taxonomy:)
      second = build(:user_interest, user: other_user, taxonomy:)
      expect(second).to be_valid
    end

    it "allows a single user to declare interest in multiple taxonomies" do
      other_taxonomy = create(:taxonomy, slug: "other-taxonomy")
      create(:user_interest, user:, taxonomy:)
      second = build(:user_interest, user:, taxonomy: other_taxonomy)
      expect(second).to be_valid
    end
  end
end
