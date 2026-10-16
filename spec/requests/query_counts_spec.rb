require "rails_helper"

# HRMS audit perf lane: pages that listed one query per day or per slip stay flat as rows grow.
RSpec.describe "Query counts that do not grow per row", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:employee) { create(:user, name: "Asha") }

  def queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def punched_day(date)
    record = create(:attendance_record, user: employee, date: date, check_in_place: "office",
                                        check_in_at: date.in_time_zone.change(hour: 9), check_out_at: date.in_time_zone.change(hour: 18))
    3.times { |i| HrLite::AttendancePunch.create!(user_id: employee.id, date: date, attendance_record_id: record.id, kind: i.even? ? "in" : "out", at: date.in_time_zone.change(hour: 9 + i)) }
  end

  it "reads every day's punches in one query on a person's month (PF-8)" do
    travel_to(Date.new(2027, 7, 20).in_time_zone.change(hour: 12)) do
      sign_in admin
      punched_day(Date.new(2027, 7, 5))
      get "/hr/admin/attendances/#{employee.id}", params: { month: "2027-07" } # warm: first-request loads
      one_day = queries { get "/hr/admin/attendances/#{employee.id}", params: { month: "2027-07" } }
      [ 6, 7, 8 ].each { |d| punched_day(Date.new(2027, 7, d)) }
      four_days = queries { get "/hr/admin/attendances/#{employee.id}", params: { month: "2027-07" } }
      expect(four_days).to eq(one_day)
    end
  end
end
