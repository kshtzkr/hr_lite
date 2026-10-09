require "rails_helper"

RSpec.describe HrLite::AttendanceRecord do
  let(:user) { create(:user) }

  describe "validations" do
    it "enforces one record per user per date" do
      create(:attendance_record, user: user, date: Date.current)
      dup = build(:attendance_record, user: user, date: Date.current)
      expect(dup).not_to be_valid
    end

    it "rejects unknown statuses and inverted punch times" do
      expect(build(:attendance_record, status: "on_moon")).not_to be_valid
      expect(build(:attendance_record, check_in_at: Time.current, check_out_at: 1.hour.ago)).not_to be_valid
    end
  end

  describe "scopes" do
    # Mid-month, so yesterday and the day before stay in this month's scope.
    before { travel_to(Time.zone.local(2027, 7, 15, 12)) }
    after { travel_back }

    it "filters by date, month, flagged and missing checkout" do
      today = create(:attendance_record, user: user, date: Date.current, check_in_at: Time.current)
      flagged = create(:attendance_record, date: Date.current - 1, flagged: true)
      closed = create(:attendance_record, date: Date.current - 2,
                      check_in_at: 2.days.ago, check_out_at: 2.days.ago + 8.hours)

      expect(described_class.for_date(Date.current)).to eq([ today ])
      expect(described_class.for_month(Date.current)).to include(today, flagged, closed)
      expect(described_class.flagged).to eq([ flagged ])
      expect(described_class.missing_checkout).to eq([ today ])
    end
  end

  describe "#worked_duration and #regularized?" do
    it "reports duration only for closed pairs" do
      now = Time.current
      open = build(:attendance_record, check_in_at: now)
      closed = build(:attendance_record, check_in_at: now, check_out_at: now + 8.hours)
      expect(open.worked_duration).to be_nil
      expect(closed.worked_duration).to eq(8.hours.to_f)
      expect(open.regularized?).to be(false)
    end
  end

  describe "#add_flag!" do
    it "accumulates notes" do
      record = build(:attendance_record)
      record.add_flag!("Check-in without GPS (denied)")
      record.add_flag!("Check-out 2.0 km from HQ")
      expect(record.flagged).to be(true)
      expect(record.flag_note).to eq("Check-in without GPS (denied); Check-out 2.0 km from HQ")
    end
  end

  describe "work hours (config.work_hours)" do
    let(:tuesday) { Date.new(2027, 7, 6) }

    def day(hours, date: tuesday, **attrs)
      start = date.in_time_zone.change(hour: 9)
      build(:attendance_record, date: date, check_in_at: start, check_out_at: start + hours.hours, **attrs)
    end

    it "is off by default" do
      expect(day(2).required_hours).to be_nil
      expect(day(2)).not_to be_short
    end

    it "needs 8h, 9h on probation, and nothing on a Saturday" do
      HrLite.config.work_hours = { day: 8, probation_day: 9, week: 40 }
      expect([ day(7.9).short?, day(8).short? ]).to eq([ true, false ])

      probationer = day(8.5, user: create(:user))
      create(:employee_profile, user: probationer.user, probation_until: tuesday)
      expect([ probationer.required_hours, probationer.short? ]).to eq([ 9, true ])
      expect(day(1, date: tuesday + 4).required_hours).to be_nil
    end

    it "measures the metres between check-in and check-out" do
      record = build(:attendance_record, check_in_lat: 28.6315, check_in_lng: 77.2167,
                                         check_out_lat: 28.6315, check_out_lng: 77.2373)
      expect(record.punch_gap_m).to be_within(10).of(2010)
      expect(build(:attendance_record, check_in_lat: 28.6).punch_gap_m).to be_nil
    end
  end
end
