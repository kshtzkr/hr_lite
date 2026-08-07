require "rails_helper"

RSpec.describe "Leave balance query cost" do
  let(:user) { create(:user, name: "Meera") }
  let(:type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 24) }

  def queries_while
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].to_s.in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  # `used` built a WorkingCalendar per approved request, and each one costs a
  # Holiday query plus a Setting query. The admin balances grid reads this
  # cell for every employee times every leave type, so the cost compounded.
  it "does not grow a query per approved leave request" do
    create(:employee_profile, user: user, date_of_joining: Date.new(2024, 1, 1))
    balance = HrLite::LeaveBalance.for(user, type, HrLite::LeaveYear.current_key)
    HrLite::Setting.instance # bootstraps its own row on first read; not the thing under test
    balance.used

    no_requests = queries_while { balance.used }

    5.times do |i|
      # Mondays: a weekend-only request consumes nothing and is rejected.
      start = Date.current.beginning_of_year.next_occurring(:monday) + (7 * i)
      HrLite::LeaveRequest.create!(user: user, leave_type: type, status: "approved",
                                   start_date: start, end_date: start,
                                   reason: "leave #{i}")
    end

    five_requests = queries_while { balance.used }

    # One calendar for the whole leave year, however many requests it covers.
    expect(five_requests).to eq(no_requests)
  end
end
