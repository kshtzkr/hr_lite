FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Person #{n}" }
    sequence(:email) { |n| "person#{n}@example.com" }
    admin { false }

    trait :admin do
      admin { true }
    end
  end
end
