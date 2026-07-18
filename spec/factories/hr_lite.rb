FactoryBot.define do
  factory :kudo, class: "HrLite::Kudo" do
    association :giver, factory: :user
    message { "Great work this week" }
  end

  factory :office_location, class: "HrLite::OfficeLocation" do
    sequence(:name) { |n| "Office #{n}" }
    lat { 28.6315 }
    lng { 77.2167 }
    radius_m { 200 }
    active { true }
  end

  factory :attendance_record, class: "HrLite::AttendanceRecord" do
    user
    sequence(:date) { |n| Date.current - n }
    status { "present" }

    trait :checked_in do
      check_in_at { Time.current.change(hour: 9, min: 30) }
    end

    trait :checked_out do
      check_in_at { Time.current.change(hour: 9, min: 30) }
      check_out_at { Time.current.change(hour: 18) }
    end

    trait :flagged do
      flagged { true }
      flag_note { "Check-in without GPS (denied)" }
    end
  end
end
