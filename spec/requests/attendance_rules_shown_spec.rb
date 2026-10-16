require "rails_helper"

# The attendance rules people are held to, said on the screen they act on.
RSpec.describe "Attendance rules on screen", type: :request do
  let(:meera) { create(:user, name: "Meera") }
  let(:wednesday) { Date.new(2026, 10, 14) }

  after { travel_back }

  it "says when to check in and what lateness costs, before Check in" do
    HrLite.config.attendance_slots = true
    travel_to(Time.zone.local(2026, 10, 14, 8, 0))
    sign_in meera
    get "/hr/attendance"
    expect(response.body).to include("Check in by <strong>10:05</strong>", "after 11:00 also 1 hour on each of the next 2 working days",
                                     "after 11:30 the day is a half day")
  end

  it "counts the day's penalty minutes in short?, the same rule as the checkout clock" do
    HrLite.config.attendance_slots = true
    HrLite.config.work_hours = { day: 8, probation_day: 9, week: 40 } # on; the day is HR's 8h 30m in Settings
    record = create(:attendance_record, user: meera, date: wednesday,
                                        check_in_at: Time.zone.local(2026, 10, 14, 10, 0), check_out_at: Time.zone.local(2026, 10, 14, 18, 40))
    expect(record).not_to be_short # 8h 40m against the 8h 30m day
    HrLite::AttendancePenalty.create!(user_id: meera.id, date: wednesday, minutes: 30, reason: "late", attendance_record: record)
    expect(record.check_out_at).to be < record.required_check_out_at
    expect(record).to be_short
  end

  it "offers word quick picks for a status, and no emoji" do
    HrLite.config.office_geofence = true
    sign_in meera
    get "/hr/attendance"
    picks = Nokogiri::HTML(response.body).css("[data-hrl-pick]").map(&:text)
    expect(picks).to include("In a meeting", "Out sick")
    expect(response.body).not_to include("data-hrl-emoji")
    expect(response.body).not_to include("Pick an emoji")
  end

  it "shows leave on the team attendance day instead of No punch, and leaves it out of the count" do
    hr = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra")
    create(:employee_profile, user: meera)
    create(:leave_request, :approved, user: meera, leave_type: create(:leave_type, code: "CL"),
                                      start_date: wednesday, end_date: wednesday)
    sign_in hr
    get "/hr/admin/attendances", params: { date: wednesday.iso8601 }
    row = Nokogiri::HTML(response.body).css("tbody tr").find { |tr| tr.text.include?("Meera") }
    expect(row.at_css("td[data-label=Status]").text).to include("On leave (CL)")
  end
end
