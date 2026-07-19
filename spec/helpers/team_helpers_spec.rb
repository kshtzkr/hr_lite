require "rails_helper"

RSpec.describe HrLite::ApplicationHelper, type: :helper do
  describe "#hrl_duration" do
    it "formats seconds as hours and minutes, em-dash for nothing" do
      expect(helper.hrl_duration(nil)).to eq("—")
      expect(helper.hrl_duration(0)).to eq("0h 00m")
      expect(helper.hrl_duration(3 * 3600 + 7 * 60)).to eq("3h 07m")
      expect(helper.hrl_duration(34_200.0)).to eq("9h 30m")
    end
  end

  describe "#hrl_team_status" do
    let(:tuesday) { Date.new(2027, 7, 6) }

    before { travel_to(tuesday.in_time_zone.change(hour: 13)) }
    after { travel_back }

    def row(kind:, record: nil, leave: nil, date: tuesday)
      HrLite::TeamDay::Row.new(kind: kind, record: record, leave: leave, date: date)
    end

    def record(date: tuesday, hour_in: 10, hour_out: nil)
      build(:attendance_record, date: date,
            check_in_at: date.in_time_zone.change(hour: hour_in),
            check_out_at: hour_out && date.in_time_zone.change(hour: hour_out))
    end

    it "renders every branch with the right label" do
      leave = build(:leave_request, leave_type: build(:leave_type, code: "CL"))

      expect(helper.hrl_team_status(row(kind: :present, record: record))).to include("In since 10:00")
      expect(helper.hrl_team_status(row(kind: :present, record: record(hour_out: 19)))).to include("Done 10:00–19:00")
      expect(helper.hrl_team_status(row(kind: :leave, leave: leave))).to include("On leave (CL)")
      expect(helper.hrl_team_status(row(kind: :half_day_leave, leave: leave))).to include("Half-day leave (CL)")
      expect(helper.hrl_team_status(row(kind: :absent))).to include("Not in yet")
      expect(helper.hrl_team_status(row(kind: :absent, date: tuesday - 1))).to include("Absent")
      expect(helper.hrl_team_status(row(kind: :upcoming))).to include("hrl-badge--muted")
      expect(helper.hrl_team_status(row(kind: :weekend))).to include("Weekend")
      expect(helper.hrl_team_status(row(kind: :holiday, record: record(hour_out: 15)))).to include("Holiday").and include("worked 10:00–15:00")
      expect(helper.hrl_team_status(row(kind: :weekend, record: record)))
        .to include("worked 10:00")
    end
  end
end
