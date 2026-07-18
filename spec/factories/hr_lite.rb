FactoryBot.define do
  factory :kudo, class: "HrLite::Kudo" do
    association :giver, factory: :user
    message { "Great work this week" }
  end
end
