require "rails_helper"

RSpec.describe "Today's check-ins on Home", type: :request do
  let(:viewer) { create(:user, name: "Ravi Kumar") }
  let(:asha) { create(:user, name: "Asha Rao") }
  let(:dev) { create(:user, name: "Dev Shah") }
  let(:meera) { create(:user, name: "Meera Iyer") }
  let(:today) { Date.new(2026, 10, 20) }

  def t(h, m = 0) = Time.zone.local(2026, 10, 20, h, m)

  before do
    travel_to(t(18, 30))
    [ viewer, asha, dev, meera ].each { |u| create(:employee_profile, user: u) }
    # Asha's slot is 09:00: 09:04 is within grace. Dev has no slot (10:00): 10:20 is late.
    HrLite::AttendanceSlot.create!(user_id: asha.id, start_minute: 540, period: "day", starts_on: today, ends_on: today)
    create(:attendance_record, user: asha, date: today, check_in_at: t(9, 4), check_out_at: t(17, 40))
    create(:attendance_record, user: dev, date: today, check_in_at: t(10, 20))
    sign_in viewer
  end

  after { travel_back }

  def section = response.body[/Today's check-ins.*?<\/section>/m]

  it "splits on time, late and not in yet, with times on hover and tap" do
    get "/hr/"
    expect(section).to include("On time · 1").and include("Late · 1").and include("Not in yet · 2")
    expect(section).to include("Asha Rao · In 09:04 · Out 17:40 · 8h 36m worked")
    expect(section).to include("Dev Shah · In 10:20 (20 min late) · 8h 10m so far")
    expect(section).to include("Meera Iyer · Not checked in yet")
  end

  it "counts an HR buffer before calling someone late" do
    HrLite::EmployeeProfile.find_by(user_id: dev.id).update!(buffer_minutes: 60, buffer_reason: "medical")
    get "/hr/"
    expect(section).to include("On time · 2").and include("Late · 0")
  end

  it "leaves people on leave out" do
    create(:leave_request, :approved, user: meera, start_date: today, end_date: today)
    get "/hr/"
    expect(section).to include("Not in yet · 1")
    expect(section).not_to include("Meera Iyer")
  end
end
