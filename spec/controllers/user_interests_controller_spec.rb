# frozen_string_literal: true

require "spec_helper"

describe UserInterestsController, type: :controller do
  let(:user) { create(:user) }
  let(:music) { Taxonomy.find_or_create_by!(slug: "music-and-sound-design") }
  let(:design) { Taxonomy.find_or_create_by!(slug: "design") }

  before { sign_in user }

  describe "POST create" do
    context "with a taxonomy_id" do
      it "creates a user interest for the given taxonomy" do
        expect do
          post :create, params: { taxonomy_id: music.id }
        end.to change { user.user_interests.count }.by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["declared_interests"].first["taxonomy"]["slug"]).to eq("music-and-sound-design")
      end

      it "is idempotent for the same taxonomy" do
        user.user_interests.create!(taxonomy: music)

        expect do
          post :create, params: { taxonomy_id: music.id }
        end.not_to change { user.user_interests.count }

        expect(response).to have_http_status(:created)
      end

      it "returns 404 for an unknown taxonomy_id" do
        post :create, params: { taxonomy_id: 999_999 }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with free_text" do
      it "creates user interests for the matched taxonomies" do
        allow(Ai::InterestMapperService).to receive(:map).with("I make album art").and_return([design])

        expect do
          post :create, params: { free_text: "I make album art" }
        end.to change { user.user_interests.count }.by(1)

        expect(response).to have_http_status(:created)
        interest = user.user_interests.last
        expect(interest.taxonomy).to eq(design)
        expect(interest.source_text).to eq("I make album art")
      end

      it "returns 422 when no taxonomies match the free text" do
        allow(Ai::InterestMapperService).to receive(:map).and_return([])

        post :create, params: { free_text: "completely unmatchable thing" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to be_present
      end

      it "returns 503 when the LLM service exhausts retries" do
        allow(Ai::InterestMapperService).to receive(:map)
          .and_raise(Ai::InterestMapperService::MaxRetriesExceededError, "boom")

        post :create, params: { free_text: "anything" }

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    it "returns 400 when neither taxonomy_id nor free_text is given" do
      post :create
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE destroy" do
    let!(:interest) { user.user_interests.create!(taxonomy: music) }

    it "removes the user interest" do
      expect do
        delete :destroy, params: { id: interest.id }
      end.to change { user.user_interests.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "does not let a user delete another user's interest" do
      other_user = create(:user)
      other_interest = other_user.user_interests.create!(taxonomy: design)

      delete :destroy, params: { id: other_interest.id }

      expect(response).to have_http_status(:not_found)
      expect(other_user.user_interests.exists?(other_interest.id)).to be(true)
    end
  end

  describe "GET recommendations" do
    let(:product) { create(:product, taxonomy: music) }

    before do
      product
      allow(Ai::RecommendationReasonService).to receive(:reason_for).and_return("Cheeky one-liner.")
    end

    it "returns recommended products for the declared taxonomy with a reason" do
      get :recommendations, params: { taxonomy_id: music.id }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["taxonomy"]["slug"]).to eq("music-and-sound-design")
      expect(body["products"].first["recommendation_reason"]).to eq("Cheeky one-liner.")
    end

    it "returns 404 for an unknown taxonomy_id" do
      get :recommendations, params: { taxonomy_id: 999_999 }
      expect(response).to have_http_status(:not_found)
    end
  end
end
