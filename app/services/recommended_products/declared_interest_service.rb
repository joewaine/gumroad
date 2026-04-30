# frozen_string_literal: true

class RecommendedProducts::DeclaredInterestService
  NUMBER_OF_RESULTS = 8
  CANDIDATES_LIMIT = 100
  PURCHASE_HISTORY_LIMIT = 50
  OVER_FETCH_MULTIPLIER = 2

  def self.fetch(user:, taxonomy:, limit: NUMBER_OF_RESULTS)
    new(user:, taxonomy:, limit:).fetch
  end

  def initialize(user:, taxonomy:, limit:)
    @user = user
    @taxonomy = taxonomy
    @limit = limit
  end

  def fetch
    return [] if user.blank? || taxonomy.blank?

    bridged = bridged_products
    return bridged if bridged.size >= limit

    fallback_exclude_ids = purchased_product_ids + bundle_product_ids + bridged.map(&:id)
    bridged + fallback_popular_in_taxonomy(exclude_ids: fallback_exclude_ids).first(limit - bridged.size)
  end

  private
    attr_reader :user, :taxonomy, :limit

    def taxonomy_ids
      @_taxonomy_ids ||= taxonomy.self_and_descendants.pluck(:id)
    end

    def purchased_product_ids
      @_purchased_product_ids ||= user.purchased_products.pluck(:id)
    end

    def bridged_products
      return [] if purchased_product_ids.empty?

      seed_ids = purchased_product_ids.last(PURCHASE_HISTORY_LIMIT)
      excluded = purchased_product_ids + bundle_product_ids

      SalesRelatedProductsInfo
        .related_products(seed_ids, limit: CANDIDATES_LIMIT)
        .where(taxonomy_id: taxonomy_ids)
        .alive
        .not_archived
        .where.not(id: excluded)
        .includes(ProductPresenter::ASSOCIATIONS_FOR_CARD)
        .first(limit * OVER_FETCH_MULTIPLIER)
        .reject(&:rated_as_adult?)
        .first(limit)
    end

    def fallback_popular_in_taxonomy(exclude_ids:)
      Link
        .where(taxonomy_id: taxonomy_ids)
        .alive
        .not_archived
        .where.not(id: exclude_ids)
        .includes(ProductPresenter::ASSOCIATIONS_FOR_CARD)
        .order(sales_count_for_inventory_cache: :desc)
        .first(limit * OVER_FETCH_MULTIPLIER)
        .reject(&:rated_as_adult?)
        .first(limit)
    end

    def bundle_product_ids
      @_bundle_product_ids ||=
        if purchased_product_ids.empty?
          []
        else
          BundleProduct.alive.where(bundle_id: purchased_product_ids).distinct.pluck(:product_id)
        end
    end
end
