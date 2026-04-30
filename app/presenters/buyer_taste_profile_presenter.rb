# frozen_string_literal: true

class BuyerTasteProfilePresenter
  def initialize(user)
    @user = user
    @service = BuyerTasteProfileService.new(user)
  end

  def props
    {
      dominant_taxonomy: serialize_taxonomy(@service.dominant_taxonomy),
      unexplored_top_levels: @service.unexplored_top_level_taxonomies.map { serialize_taxonomy(_1) },
      declared_interests: declared_interests_props,
    }
  end

  def serialize_taxonomy(taxonomy)
    return nil if taxonomy.blank?
    {
      id: taxonomy.id,
      slug: taxonomy.slug,
      label: self.class.label_for(taxonomy),
    }
  end

  def serialize_interest(interest)
    {
      id: interest.id,
      taxonomy: serialize_taxonomy(interest.taxonomy),
      source_text: interest.source_text,
    }
  end

  def self.label_for(taxonomy)
    taxonomy.slug.tr("-", " ").gsub(" and ", " & ").capitalize
  end

  private
    def declared_interests_props
      @user.user_interests.includes(:taxonomy).map { serialize_interest(_1) }
    end
end
