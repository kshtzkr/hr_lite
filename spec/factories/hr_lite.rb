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

  factory :leave_type, class: "HrLite::LeaveType" do
    sequence(:name) { |n| "Leave #{n}" }
    sequence(:code) { |n| "L#{n}" }
    color { "#0ea5e9" }
    paid { true }
    annual_quota { 12 }
    accrual { "yearly_upfront" }
    carry_forward_cap { 0 }
    active { true }

    trait :monthly do
      accrual { "monthly" }
    end

    trait :unpaid_unlimited do
      paid { false }
      annual_quota { nil }
    end
  end

  factory :holiday, class: "HrLite::Holiday" do
    sequence(:date) { |n| Date.current.beginning_of_year + (n * 11) }
    sequence(:name) { |n| "Holiday #{n}" }

    trait :optional do
      optional { true }
    end
  end

  factory :leave_balance, class: "HrLite::LeaveBalance" do
    user
    leave_type
    year { Date.current.year }
  end

  factory :leave_request, class: "HrLite::LeaveRequest" do
    user
    leave_type
    start_date { Date.current.next_occurring(:tuesday) }
    end_date { Date.current.next_occurring(:tuesday) }

    trait :approved do
      status { "approved" }
    end
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
