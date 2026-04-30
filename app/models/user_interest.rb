# frozen_string_literal: true

class UserInterest < ApplicationRecord
  SOURCE_TEXT_MAX_LENGTH = 200

  belongs_to :user
  belongs_to :taxonomy

  validates :user_id, uniqueness: { scope: :taxonomy_id }
  validates :source_text, length: { maximum: SOURCE_TEXT_MAX_LENGTH }, allow_nil: true
end
