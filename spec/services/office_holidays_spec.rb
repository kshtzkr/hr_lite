require "rails_helper"

# A holiday for one office is a paid day off there and an ordinary working
# day everywhere else — in attendance, leave counting, payroll and status.
RSpec.describe "Holidays per office" do
  let(:noida) { create(:office_location, name: "Noida") }
  let(:goa) { create(:office_location, name: "Goa") }
  let!(:ana) { create(:employee_profile, office_location: noida).user }
  let!(:bob) { create(:employee_profile, office_location: goa).user }
  let(:nomad) { create(:employee_profile).user } # no office: all-office holidays only
  let(:month) { Date.new(2027, 7, 1) }
  let(:noida_day) { Date.new(2027, 7, 6) } # a Tuesday

  before { create(:holiday, date: noida_day, name: "Noida foundation day", office_location: noida) }

  it "pays the holiday to that office only; elsewhere an unpunched day is loss of pay" do
    travel_to(Date.new(2027, 8, 5)) do
      ana_month = HrLite::AttendanceSummary.for(user: ana, month: month)
      bob_month = HrLite::AttendanceSummary.for(user: bob, month: month)
      expect(ana_month[:holiday]).to eq(1)
      expect(bob_month[:holiday]).to eq(0)
      expect(ana_month[:lop_days]).to eq(bob_month[:lop_days] - 1)
      expect(ana_month[:payable_days] + ana_month[:lop_days]).to eq(31)
    end
  end

  it "takes the office holiday out of a leave only for that office" do
    type = create(:leave_type, annual_quota: 12)
    span = { leave_type: type, start_date: noida_day - 1, end_date: noida_day + 1 } # Mon–Wed
    expect(HrLite::LeaveDayCounter.count(build(:leave_request, user: ana, **span))).to eq(2)
    expect(HrLite::LeaveDayCounter.count(build(:leave_request, user: bob, **span))).to eq(3)
    expect(HrLite::LeaveDayCounter.count(build(:leave_request, user: nomad, **span))).to eq(3)
  end

  it "still gives every office an all-office holiday" do
    create(:holiday, date: noida_day + 1, name: "National day")
    [ ana, bob, nomad ].each do |user|
      expect(HrLite::WorkingCalendar.for_user(user.id, month.all_month).holiday?(noida_day + 1)).to be(true)
    end
  end

  it "lets two offices close on one date, but not one office twice" do
    expect(create(:holiday, date: noida_day, name: "Goa day", office_location: goa)).to be_persisted
    expect(build(:holiday, date: noida_day, name: "Again", office_location: noida)).not_to be_valid
    create(:holiday, date: noida_day, name: "Everyone")
    expect(build(:holiday, date: noida_day, name: "Everyone again")).not_to be_valid
  end

  it "skips the office's people at day close and shows them on holiday" do
    travel_to(Time.zone.local(2027, 7, 6, 23, 55)) do
      notified = []
      allow(HrLite::Notifications).to receive(:publish) { |event, **opts| notified << [ event, opts[:bell_to] ] }
      HrLite::AttendanceCloseJob.perform_now(date: noida_day)
      missed = notified.select { |event, _| event == "attendance.missed_check_in" }.flat_map(&:last)
      expect(missed).to include(bob)
      expect(missed).not_to include(ana)

      statuses = HrLite::WorkStatus.for_users([ ana.id, bob.id ])
      expect(statuses[ana.id].primary.mode).to eq("holiday")
      expect(statuses[bob.id].primary.mode).to eq("offline")
      board = HrLite::TeamDay.new(date: noida_day).rows.index_by { |r| r.user.id }
      expect([ board[ana.id].kind, board[bob.id].kind ]).to eq([ :holiday, :absent ])
    end
  end

  it "accepts a comp-off for working the office holiday only from that office" do
    travel_to(Date.new(2027, 7, 10)) do
      expect(build(:comp_off_request, user: ana, date_worked: noida_day)).to be_valid
      expect(build(:comp_off_request, user: bob, date_worked: noida_day)).not_to be_valid
    end
  end
end
