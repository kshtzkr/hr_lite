require "rails_helper"

RSpec.describe "Full day / first half / second half", type: :request do
  let(:leader) { create(:user, name: "Khushboo", email: "lead@example.com", admin: true) }
  let(:employee) { create(:user, name: "Asha") }
  let(:monday) { Date.new(2027, 7, 5) }

  before do
    HrLite.config.leadership_emails = [ leader.email ]
    create(:employee_profile, user: employee, date_of_joining: Date.new(2025, 1, 1))
    travel_to(Date.new(2027, 7, 1))
  end

  after { travel_back }

  it "books a first-half leave as half a day" do
    request = create(:leave_request, user: employee, leave_type: create(:leave_type, annual_quota: 12),
                     start_date: monday, end_date: monday, half_day_part: "first")

    expect(request.half_day).to be(true)
    expect(request.days_count).to eq(0.5)
    expect(request.date_range_label).to eq("05 Jul (first half)")
  end

  it "lets HR mark a punched day as second half, then back to full day" do
    record = HrLite::AttendanceRecord.create!(user: employee, date: monday, status: "present",
                                              check_in_at: monday.in_time_zone.change(hour: 9))
    sign_in leader
    update = ->(part) {
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: monday.iso8601,
        attendance_record: { check_in_at: "#{monday}T09:00", check_out_at: "", half_day_part: part,
                             regularization_note: "told us later" }
      }
    }

    update.call("second")
    expect(record.reload).to have_attributes(status: "half_day", half_day_part: "second")

    update.call("")
    expect(record.reload).to have_attributes(status: "present", half_day_part: nil)
  end
end
