require "rails_helper"

RSpec.describe "Attendance slots and late penalties", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:admin) { create(:user, :admin) }
  let(:friday) { Date.new(2026, 10, 16) }

  before { HrLite.config.attendance_slots = true }
  after { travel_back }

  def at(date, hour, min) = Time.zone.local(date.year, date.month, date.day, hour, min)

  def check_in(time)
    travel_to(time)
    sign_in employee
    post "/hr/attendance/check_in"
  end

  def penalties = HrLite::AttendancePenalty.where(user_id: employee.id).order(:date).pluck(:date, :minutes, :reason)

  def lock_slot(minute)
    HrLite::AttendanceSlot.create!(user_id: employee.id, start_minute: minute, period: "day", starts_on: friday, ends_on: friday)
  end

  it "steps +30 per started half hour after 5 minutes of grace" do
    expect([ 5, 6, 35, 36, 65, 66 ].map { |late| HrLite::AttendanceSlot.penalty_minutes(late) })
      .to eq([ 0, 30, 30, 60, 60, 90 ])
  end

  it "adds the late penalty to the day's checkout" do
    lock_slot(540)
    check_in(at(friday, 9, 36))

    expect(penalties).to eq([ [ friday, 60, "late" ] ])
    # Hours worked: 09:36 + 8h30 + the 60-minute penalty.
    expect(HrLite::AttendanceRecord.find_by(user_id: employee.id).required_check_out_at).to eq(at(friday, 19, 6))
    get "/hr/attendance"
    expect(response.body).to include("checkout at <strong>19:06</strong>").and include("+60 min")
    expect(response.body).to include(%(data-hrl-countdown="#{at(friday, 19, 6).iso8601}" data-hrl-done="you can check out">))
  end

  it "charges nothing on a weekly off or on a day that starts on approved leave" do
    create(:leave_request, :approved, user: employee, start_date: friday, end_date: friday, half_day_part: "first")
    check_in(at(friday, 14, 0))
    check_in(at(friday + 1, 13, 0)) # Saturday
    expect(penalties).to be_empty
    expect(HrLite::AttendanceRecord.where(user_id: employee.id).pluck(:status)).to eq(%w[present present])
  end

  it "uses the 10:00 slot when none is saved" do
    check_in(at(friday, 10, 5))
    expect(penalties).to be_empty
  end

  it "after 11:00 also carries +1h to the next two working days, skipping the weekend" do
    lock_slot(540)
    check_in(at(friday, 11, 1))

    expect(penalties).to eq([ [ friday, 120, "late" ], [ friday + 3, 60, "late_carry" ], [ friday + 4, 60, "late_carry" ] ])
    expect(HrLite::AttendanceRecord.find_by(user_id: employee.id).status).to eq("present")
  end

  it "after 11:30 makes the day a half day" do
    check_in(at(friday, 11, 31))
    expect(HrLite::AttendanceRecord.find_by(user_id: employee.id).status).to eq("half_day")
  end

  it "delays the penalty clock by the HR buffer" do
    create(:employee_profile, user: employee, buffer_minutes: 60, buffer_reason: "medical")
    lock_slot(540)
    check_in(at(friday, 10, 5))
    expect(penalties).to be_empty
  end

  it "locks a saved slot until HR unlocks it" do
    travel_to(at(friday, 8, 0))
    sign_in employee
    get "/hr/attendance"
    expect(response.body).to include(%(name="period" value="week" class="hrl-btn" data-turbo-confirm="Lock this slot for this week? After that only HR can change it.">This week</button>))
    post "/hr/attendance/slot", params: { start_minute: 570, period: "week" }
    expect(HrLite::AttendanceSlot.current(employee.id, friday + 2).start_minute).to eq(570)

    post "/hr/attendance/slot", params: { start_minute: 600, period: "day" }
    expect(flash[:alert]).to include("locked")

    sign_in admin
    post "/hr/admin/attendances/#{employee.id}/unlock_slot"
    sign_in employee
    post "/hr/attendance/slot", params: { start_minute: 600, period: "day" }
    expect(HrLite::AttendanceSlot.current(employee.id, friday).start_minute).to eq(600)
  end

  it "refuses a slot pick after today's check-in" do
    check_in(at(friday, 10, 40))
    post "/hr/attendance/slot", params: { start_minute: 630, period: "day" }
    expect(flash[:alert]).to include("before checking in")
  end

  it "lets HR remove a penalty only with a reason" do
    lock_slot(540)
    check_in(at(friday, 9, 10))
    penalty = HrLite::AttendancePenalty.last
    sign_in admin

    post "/hr/admin/attendances/#{employee.id}/remove_penalty", params: { penalty_id: penalty.id }
    expect(penalty.reload.removed_at).to be_nil

    post "/hr/admin/attendances/#{employee.id}/remove_penalty", params: { penalty_id: penalty.id, removal_reason: "Told HR" }
    expect(penalty.reload.removal_reason).to eq("Told HR")
    expect(HrLite::AttendanceRecord.find_by(user_id: employee.id).required_check_out_at).to eq(at(friday, 17, 40))
  end

  it "puts +30 min on the next working day when the close job finds a short day" do
    lock_slot(540)
    create(:attendance_record, user: employee, date: friday, check_in_at: at(friday, 9, 0), check_out_at: at(friday, 17, 0))
    travel_to(at(friday, 23, 55))
    HrLite::AttendanceCloseJob.perform_now(date: friday)
    HrLite::AttendanceCloseJob.perform_now(date: friday)

    expect(penalties).to eq([ [ friday + 3, 30, "short_day" ] ])
  end
end
