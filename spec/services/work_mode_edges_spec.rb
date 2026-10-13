require "rails_helper"

RSpec.describe "Work-mode edges" do
  let(:asha) { create(:user, name: "Asha") }
  let(:day) { Date.new(2026, 10, 20) }

  def t(h, m = 0) = Time.zone.local(2026, 10, 20, h, m)

  describe HrLite::WorkModeDurations::Period do
    it "labels and builds every kind" do
      expect(described_class.build("day", day).label).to eq("Tuesday 20 October 2026")
      expect(described_class.build("month", day).label).to eq("October 2026")
      expect(described_class.build("quarter", day).label).to eq("Q4 2026")
      expect(described_class.build("year", day).label).to eq("2026")
      expect(described_class.build("week", day).label).to eq("19 Oct 2026 – 25 Oct 2026")
    end
  end

  it "keeps one stretch when an overlay runs across two work modes" do
    [ [ "office", "primary", t(9), t(12) ], [ "wfh", "primary", t(12), t(18) ], [ "busy", "overlay", t(10), t(14) ] ].each do |mode, _layer, from, to|
      HrLite::WorkModeEvent.create!(user_id: asha.id, mode: mode, source: "employee", started_at: from, ended_at: to)
    end
    result = HrLite::WorkModeDurations.call([ asha.id ], HrLite::WorkModeDurations::Period.build("day", day), now: t(20))
    expect(result.segments.map(&:mode)).to eq(%w[office busy wfh])
    expect(result.by_mode["busy"]).to eq(4.hours)
  end

  describe HrLite::WorkModeSwitch do
    before do
      HrLite.config.office_geofence = true
      travel_to(t(11))
      record = create(:attendance_record, user: asha, date: day, check_in_at: t(9))
      HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record, at: t(9))
    end

    after { travel_back }

    def switch(mode, **params) = described_class.call(user: asha, mode: mode, source: "employee", actor: asha, params: params)

    it "needs a title for a meeting and a reason for being out, then sets out of office until a time" do
      expect(switch("meeting").error).to include("title")
      expect(switch("meeting", title: "Standup", until: "11:30").event).to have_attributes(title: "Standup", ends_at: t(11, 30))
      expect(switch("out_of_office", until: "12:00").error).to include("reason")
      expect(switch("out_of_office", category: "family", until: "12:00").event).to have_attributes(title: "Family", ends_at: t(12))
    end

    it "refuses an end time it cannot read" do
      expect(switch("busy", until: "99:99").error).to include("when it ends")
    end

    it "switches to WFH with today's approval, using the active home" do
      HrLite::WfhRequest.new(user_id: asha.id, start_date: day, end_date: day, reason: "x", status: "approved").save!(validate: false)
      home = HrLite::WorkLocation.create!(user_id: asha.id, name: "Home", lat: 1, lng: 1, accuracy_m: 10, status: "approved", active: true)
      expect(switch("wfh").event).to have_attributes(mode: "wfh", work_location_id: home.id)
    end

    it "reports a record the database refuses" do
      allow(HrLite::WorkModeEvent).to receive(:start!).and_raise(ActiveRecord::RecordInvalid.new(HrLite::WorkModeEvent.new.tap { |e| e.errors.add(:base, "Nope") }))
      expect(switch("lunch").error).to eq("Nope")
    end
  end

  it "lets a racing calendar start lose quietly" do
    HrLite.config.office_geofence = true
    HrLite.config.calendar_events = ->(_u, _f, _t) { [ { id: "e1", title: "Sync", starts_at: t(10, 59), ends_at: t(11, 30) } ] }
    travel_to(t(11)) do
      record = create(:attendance_record, user: asha, date: day, check_in_at: t(9))
      HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record, at: t(9))
      allow(HrLite::WorkModeEvent).to receive(:start!).and_raise(ActiveRecord::RecordNotUnique)
      expect { HrLite::CalendarMeetingStartJob.perform_now(asha.id, "e1") }.not_to raise_error
    end
  end
end
