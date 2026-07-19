require "rails_helper"

RSpec.describe "Team board", type: :request do
  let(:viewer) { create(:user, name: "Asha") }
  let(:worker) { create(:user, name: "Meera") }
  let(:absentee) { create(:user, name: "Dev") }
  let(:type) { create(:leave_type, name: "Casual", code: "CL", annual_quota: 12) }
  # Thursday, mid-month.
  let(:today) { Date.new(2027, 7, 8) }

  around { |example| travel_to(today.in_time_zone.change(hour: 14)) { example.run } }
  before { sign_in viewer }

  it "shows who's in (running clock), who's done, who's absent, who's on leave" do
    create(:attendance_record, user: worker, date: today,
           check_in_at: today.in_time_zone.change(hour: 10, min: 2))
    leave = create(:leave_request, user: create(:user, name: "Priya"), leave_type: type,
                   start_date: today, end_date: today)
    leave.update!(status: "approved")
    absentee

    get "/hr/team"
    expect(response.body).to include("In since 10:02")
    expect(response.body).to include("On leave (CL)")
    expect(response.body).to include("Not in yet")
    # 4h between 10:02 and 14:00 — the running clock counts 3h 58m.
    expect(response.body).to include("3h 58m")
  end

  it "shows finished punches and month totals for a past date" do
    yesterday = today - 1
    create(:attendance_record, user: worker, date: yesterday,
           check_in_at: yesterday.in_time_zone.change(hour: 10),
           check_out_at: yesterday.in_time_zone.change(hour: 19, min: 30))

    get "/hr/team", params: { date: yesterday.strftime("%Y-%m-%d") }
    expect(response.body).to include("Done 10:00–19:30")
    expect(response.body).to include("9h 30m")
    expect(response.body).to include("Absent") # viewer, past working day, no punch
  end

  it "labels weekends, surfaces off-day work, and hides exited staff" do
    sunday = Date.new(2027, 7, 4)
    create(:attendance_record, user: worker, date: sunday,
           check_in_at: sunday.in_time_zone.change(hour: 11),
           check_out_at: sunday.in_time_zone.change(hour: 15))
    gone = create(:user, name: "Exited Person")
    create(:employee_profile, user: gone, date_of_exit: Date.new(2027, 1, 31))

    get "/hr/team", params: { date: "2027-07-04" }
    expect(response.body).to include("Weekend")
    expect(response.body).to include("worked 11:00–15:00")
    expect(response.body).not_to include("Exited Person")
  end

  it "marks holidays and future dates" do
    create(:holiday, date: Date.new(2027, 7, 9), name: "Festival")
    get "/hr/team", params: { date: "2027-07-09" }
    expect(response.body).to include("Holiday")

    get "/hr/team", params: { date: "2027-07-12" }
    expect(response.body).to include("hrl-badge--muted")
  end

  it "shows KPI counts and half-day leaves" do
    record = create(:attendance_record, user: worker, date: today,
                    check_in_at: today.in_time_zone.change(hour: 10))
    half = create(:leave_request, user: viewer, leave_type: type,
                  start_date: today, end_date: today, half_day: true)
    half.update!(status: "approved")

    get "/hr/team"
    expect(response.body).to include("Half-day leave (CL)")
    expect(response.body).to include("Checked in")
    expect(record.user_id).to eq(worker.id)
  end

  it "falls back to today on garbage dates" do
    get "/hr/team", params: { date: "not-a-date" }
    expect(response.body).to include("Team — today")
  end
end
