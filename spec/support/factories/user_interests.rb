# frozen_string_literal: true

FactoryBot.define do
  factory :user_interest do
    association :user
    association :taxonomy

    trait :from_free_text do
      source_text { "music production tools" }
    end
  end
end
