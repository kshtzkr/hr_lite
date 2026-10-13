require "rails_helper"

RSpec.describe HrLite::WorkModeDurations do
  let(:asha) { create(:user, name: "Asha") }
  let(:day) { Date.new(2026, 10, 20) } # a Tuesday

  def t(hour, min = 0, date: day) = Time.zone.local(date.year, date.month, date.day, hour, min)

  def ev(mode, from, to, source: "employee", user: asha, ends_at: nil)
    HrLite::WorkModeEvent.create!(user_id: user.id, mode: mode, source: source, started_at: from, ended_at: to,
                                  end_reason: (to && "switched"), ends_at: ends_at)
  end

  def period(kind, date = day, **opts) = HrLite::WorkModeDurations::Period.build(kind, date, **opts)
  def run(kind = "day", now: t(20), **opts) = described_class.call([ asha.id ], period(kind, **opts), now: now)

  # The owner's example: 9:00 check-in, 18:00 check-out.
  def owners_day
    create(:attendance_record, user: asha, date: day, check_in_at: t(9), check_out_at: t(18))
    ev("office", t(9), t(15, 30), source: "system")
    ev("busy", t(11), t(12))
    ev("meeting", t(12), t(12, 30))
    ev("lunch", t(13), t(13, 30))
    ev("outside_meeting", t(15, 30), t(17))
    ev("office", t(17), t(18))
    ev("offline", t(18), nil, source: "system")
  end

  it "adds the owner's day up exactly, a break never counted twice" do
    owners_day
    r = run
    expect(r.by_mode.transform_values { |s| s / 60 }).to include("office" => 330, "busy" => 60, "meeting" => 30,
                                                                  "lunch" => 30, "outside_meeting" => 90, "offline" => 120)
    expect([ r.attendance, r.working, r.breaks, r.other ].map { |s| s / 3600.0 }).to eq([ 9.0, 8.5, 0.5, 0.0 ])
    expect(r.tracked).to eq(r.attendance)
    expect(r.segments.map(&:mode).first(4)).to eq(%w[office busy meeting office])
    expect(r.by_source["system"] / 3600.0).to eq(4.5) # office 9–11, 12:30–13, 13:30–15:30
  end

  it "runs an open mode to now, and an overrun break only to its end time" do
    create(:attendance_record, user: asha, date: day, check_in_at: t(9))
    ev("office", t(9), nil, source: "system")
    ev("lunch", t(13), nil, ends_at: t(13, 30))
    r = run(now: t(14))
    expect(r.by_mode["lunch"]).to eq(30.minutes)
    expect(r.by_mode["office"]).to eq(4.5.hours)
    expect(r.attendance).to eq(5.hours)
  end

  it "buckets a day by hour, a week by day, a quarter by week, a year by month" do
    owners_day
    expect(run.by_bucket[11]["busy"]).to eq(1.hour)
    week = run("week")
    expect(week.by_bucket.keys).to eq((Date.new(2026, 10, 19)..day).to_a) # nothing past "now"
    expect(week.by_bucket[day].values.sum).to eq(9.hours + 2.hours) # incl. offline 18–20
    expect(run("quarter").by_bucket.keys.first).to eq(Date.new(2026, 9, 28))
    expect(run("year").by_bucket.keys.last).to eq(Date.new(2026, 10, 1))
  end

  it "clips intervals at the edges of a custom range and splits across midnight" do
    ev("offline", t(18, date: day - 1), t(9), source: "system")
    r = run("custom", now: t(20), from: day, to: day)
    expect(r.by_mode["offline"]).to eq(9.hours)
    expect(run("custom", from: day - 1, to: day).by_bucket[day - 1]["offline"]).to eq(6.hours)
  end

  it "refuses an impossible custom range" do
    expect { period("custom", from: day, to: day - 1) }.to raise_error(ArgumentError, /after the end/)
    expect { period("custom", from: day - 400, to: day) }.to raise_error(ArgumentError, /366/)
  end

  it "tells no data apart from zero" do
    r = run
    expect(r.days_with_data).to be_empty
    expect(r.working).to eq(0)
    owners_day
    expect(run.days_with_data).to eq(Set[day])
  end

  it "flags gaps: a missing check-out, a day without modes, modes without a check-in" do
    create(:attendance_record, user: asha, date: day - 1, check_in_at: t(9, date: day - 1))
    create(:attendance_record, user: asha, date: day, check_in_at: t(9), check_out_at: t(17))
    ev("busy", t(10, date: day - 2), t(11, date: day - 2))
    reasons = run("custom", from: day - 2, to: day).gaps.map(&:last)
    expect(reasons).to contain_exactly("Check-out missing", "Checked in, but no work mode recorded",
                                       "Work modes recorded without a check-in")
  end

  it "sums several people without mixing their slices" do
    owners_day
    dev = create(:user, name: "Dev")
    ev("office", t(9), t(10), user: dev)
    r = described_class.call([ asha.id, dev.id ], period("day"), now: t(20))
    expect(r.by_mode["office"]).to eq(6.5.hours)
  end
end
