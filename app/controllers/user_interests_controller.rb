# frozen_string_literal: true

class UserInterestsController < ApplicationController
  RECOMMENDATIONS_LIMIT = 8

  before_action :authenticate_user!

  def create
    if params[:taxonomy_id].present?
      taxonomy = Taxonomy.find_by(id: params[:taxonomy_id])
      return render json: { error: "Taxonomy not found" }, status: :not_found if taxonomy.blank?

      interest = logged_in_user.user_interests.find_or_create_by!(taxonomy:)
      render json: { declared_interests: [serialize_interest(interest)] }, status: :created
    elsif params[:free_text].present?
      taxonomies = Ai::InterestMapperService.map(params[:free_text])

      if taxonomies.empty?
        return render json: { error: "We couldn't find a matching category for that." }, status: :unprocessable_entity
      end

      interests = taxonomies.map do |taxonomy|
        logged_in_user.user_interests.find_or_create_by!(taxonomy:) do |ui|
          ui.source_text = params[:free_text]
        end
      end

      render json: { declared_interests: interests.map { serialize_interest(_1) } }, status: :created
    else
      render json: { error: "taxonomy_id or free_text is required" }, status: :bad_request
    end
  rescue Ai::InterestMapperService::InvalidPromptError => e
    render json: { error: e.message }, status: :bad_request
  rescue Ai::InterestMapperService::MaxRetriesExceededError
    render json: { error: "Couldn't reach our matching service right now. Try again." }, status: :service_unavailable
  end

  def destroy
    interest = logged_in_user.user_interests.find_by(id: params[:id])
    return render json: { error: "Not found" }, status: :not_found if interest.blank?

    interest.destroy!
    head :no_content
  end

  def recommendations
    taxonomy = Taxonomy.find_by(id: params[:taxonomy_id])
    return render json: { error: "Taxonomy not found" }, status: :not_found if taxonomy.blank?

    products = RecommendedProducts::DeclaredInterestService.fetch(user: logged_in_user, taxonomy:, limit: RECOMMENDATIONS_LIMIT)
    reasons = parallel_recommendation_reasons(products, taxonomy)
    render json: {
      taxonomy: serialize_taxonomy(taxonomy),
      products: products.map { serialize_recommended_product(_1, reasons[_1.id]) }
    }
  end

  private
    def serialize_interest(interest)
      presenter.serialize_interest(interest)
    end

    def serialize_taxonomy(taxonomy)
      presenter.serialize_taxonomy(taxonomy)
    end

    def serialize_recommended_product(product, reason)
      ProductPresenter.card_for_web(product:, request:).merge(recommendation_reason: reason)
    end

    def parallel_recommendation_reasons(products, declared_taxonomy)
      label = BuyerTasteProfilePresenter.label_for(declared_taxonomy)
      threads = products.map do |product|
        Thread.new do
          reason =
            begin
              Ai::RecommendationReasonService.reason_for(user: logged_in_user, product:, declared_interest_label: label)
            rescue StandardError => e
              Rails.logger.warn("RecommendationReason thread fell back for product=#{product.id}: #{e.class}: #{e.message}")
              Ai::RecommendationReasonService::FALLBACK_REASON
            end
          [product.id, reason]
        end
      end
      threads.to_h(&:value)
    end

    def presenter
      @_presenter ||= BuyerTasteProfilePresenter.new(logged_in_user)
    end
end
