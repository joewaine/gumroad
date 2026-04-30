# frozen_string_literal: true

class BuyerTasteProfileService
  UNEXPLORED_LIMIT = 6

  def initialize(user)
    @user = user
  end

  def dominant_taxonomy
    @_dominant ||= Taxonomy.find_by(id: dominant_taxonomy_id)
  end

  def purchased_taxonomy_distribution
    @_distribution ||=
      @user.purchased_products
        .where.not(taxonomy_id: nil)
        .group(:taxonomy_id)
        .order(Arel.sql("COUNT(*) DESC"))
        .count
  end

  def unexplored_top_level_taxonomies(limit: UNEXPLORED_LIMIT)
    excluded_root_ids = root_taxonomy_ids_for(purchased_taxonomy_ids) | root_taxonomy_ids_for(declared_taxonomy_ids)
    Taxonomy.where(parent_id: nil).where.not(id: excluded_root_ids).order(:slug).limit(limit)
  end

  private
    def dominant_taxonomy_id
      purchased_taxonomy_distribution.first&.first
    end

    def purchased_taxonomy_ids
      purchased_taxonomy_distribution.keys
    end

    def declared_taxonomy_ids
      @_declared_ids ||= @user.declared_interest_taxonomies.pluck(:id)
    end

    def root_taxonomy_ids_for(taxonomy_ids)
      return [] if taxonomy_ids.empty?
      Taxonomy.where(id: taxonomy_ids).map { _1.root.id }.uniq
    end
end
