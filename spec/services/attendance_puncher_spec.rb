require "rails_helper"

RSpec.describe HrLite::AttendancePuncher do
  let(:user) { create(:user) }

  def punch(kind, **kw)
    described_class.call(user: user, kind: kind, **kw)
  end

  describe "check-in" do
    it "creates today's record with coordinates" do
      result = punch(:check_in, lat: "28.6315", lng: "77.2167", accuracy_m: "18", geo_status: "ok")

      expect(result).to be_ok
      record = result.record
      expect(record.date).to eq(Date.current)
      expect(record.check_in_at).to be_present
      expect(record.check_in_lat).to eq(28.6315)
      expect(record.check_in_accuracy_m).to eq(18)
      expect(record.flagged).to be(false)
    end

    it "rejects a duplicate check-in with the original time" do
      travel_to(Time.zone.parse("#{Date.current} 09:02")) { punch(:check_in) }
      result = punch(:check_in)
      expect(result).not_to be_ok
      expect(result.error).to include("Already checked in at 09:02")
    end
  end

  describe "check-out" do
    it "closes today's punch; a repeat overwrites (last out wins)" do
      # Anchored mid-day: run near midnight, "+2 hours" must not cross
      # into tomorrow (the repeat would then miss today's record).
      travel_to(Time.zone.parse("#{Date.current} 14:00"))
      punch(:check_in)
      first = punch(:check_out)
      expect(first).to be_ok

      travel_to(2.hours.from_now)
      second = punch(:check_out)
      expect(second.record.check_out_at).to be > first.record.check_out_at
      travel_back
    end

    it "refuses without an open check-in" do
      result = punch(:check_out)
      expect(result.error).to eq("No open check-in to close.")
    end

    it "closes yesterday's open record after midnight" do
      yesterday_evening = (Date.current - 1).in_time_zone.change(hour: 21)
      record = create(:attendance_record, user: user, date: Date.current - 1, check_in_at: yesterday_evening)

      result = punch(:check_out)
      expect(result).to be_ok
      expect(result.record).to eq(record)
      expect(record.reload.check_out_at).to be_present
    end

    it "prefers today's open record over yesterday's" do
      create(:attendance_record, user: user, date: Date.current - 1, check_in_at: 30.hours.ago)
      punch(:check_in)

      result = punch(:check_out)
      expect(result.record.date).to eq(Date.current)
    end
  end

  describe "flagging" do
    it "flags punches without GPS but records them" do
      result = punch(:check_in, geo_status: "denied")
      expect(result).to be_ok
      expect(result.record.flag_note).to eq("Check-in without GPS (denied)")
    end

    it "distinguishes timeout and unavailable" do
      expect(punch(:check_in, geo_status: "timeout").record.flag_note).to include("(timeout)")
    end

    it "labels missing coords with ok status as unavailable" do
      expect(punch(:check_in, geo_status: "ok").record.flag_note).to include("(unavailable)")
    end

    it "flags out-of-radius punches with distance and accuracy" do
      create(:office_location, name: "HQ", lat: 28.6315, lng: 77.2167, radius_m: 200)
      result = punch(:check_in, lat: 28.6129, lng: 77.2295, accuracy_m: 40)

      expect(result.record.flagged).to be(true)
      expect(result.record.flag_note).to match(/Check-in \d+(\.\d+)? km from HQ \(±40 m\)/)
    end

    it "does not flag in-radius punches" do
      create(:office_location, lat: 28.6315, lng: 77.2167, radius_m: 200)
      expect(punch(:check_in, lat: 28.6316, lng: 77.2168).record.flagged).to be(false)
    end

    it "never flags by radius when no offices are configured" do
      expect(punch(:check_in, lat: 12.0, lng: 77.0).record.flagged).to be(false)
    end

    it "accumulates a checkout flag onto a clean check-in" do
      create(:office_location, lat: 28.6315, lng: 77.2167, radius_m: 200)
      punch(:check_in, lat: 28.6315, lng: 77.2167)
      result = punch(:check_out, geo_status: "denied")
      expect(result.record.flag_note).to eq("Check-out without GPS (denied)")
    end

    it "bells admins when a punch gets flagged" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      create(:user, :admin)

      punch(:check_in, geo_status: "denied")
      expect(bells.map { |b| b[:kind] }).to include("attendance.flagged")
    end

    it "does not re-notify an unflagged clean punch" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      create(:user, :admin)

      punch(:check_in, lat: 12.0, lng: 77.0)
      expect(bells).to be_empty
    end
  end

  it "rejects unknown punch kinds" do
    expect(punch(:lunch).error).to include("Unknown punch")
  end

  it "survives the create race via the unique index" do
    call_count = 0
    allow(HrLite::AttendanceRecord).to receive(:find_or_create_by!).and_wrap_original do |m, *args, **kw|
      call_count += 1
      raise ActiveRecord::RecordNotUnique, "race" if call_count == 1

      m.call(*args, **kw)
    end

    expect(punch(:check_in)).to be_ok
  end
end
