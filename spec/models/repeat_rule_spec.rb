require "rails_helper"

RSpec.describe HrLite::RepeatRule do
  let(:from) { Date.new(2026, 10, 19) } # a Monday

  def dates(rule, span = 0..20) = span.map { |i| from + i }.select { |date| rule.occurs_on?(date) }

  it "repeats every N days, every N weeks on chosen weekdays, or every N months on the start's date" do
    expect(dates(described_class.new(freq: "DAILY", interval: 3, from: from), 0..9)).to eq([ from, from + 3, from + 6, from + 9 ])
    expect(dates(described_class.new(freq: "WEEKLY", interval: 2, days: %w[MO FR], from: from)).map(&:day)).to eq([ 19, 23, 2, 6 ])
    expect(dates(described_class.new(freq: "MONTHLY", from: from), -5..70)).to eq([ from, Date.new(2026, 11, 19), Date.new(2026, 12, 19) ])
    expect(described_class.new(freq: "YEARLY", from: "junk")).to have_attributes(freq: "DAILY", from: Date.current)
  end

  it "ends on a date or after N times, and reads back like a calendar" do
    rule = described_class.parse("FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR;DTSTART=2026-10-19;COUNT=4")
    expect(dates(rule)).to eq([ from, from + 2, from + 4, from + 7 ])
    expect(rule.describe).to eq("Every week on Mon, Wed, Fri from 19 Oct 2026, 4 times")

    ending = described_class.from_params(freq: "DAILY", interval: "2", from: "2026-10-19", ends: "on", until: "2026-10-23", count: "9")
    expect([ dates(ending), ending.to_s ]).to eq([ [ from, from + 2, from + 4 ], "FREQ=DAILY;INTERVAL=2;DTSTART=2026-10-19;UNTIL=2026-10-23" ])
    expect(ending.describe).to eq("Every 2 days from 19 Oct 2026, until 23 Oct 2026")
    expect([ described_class.parse(""), described_class.from_params(freq: "") ]).to eq([ nil, nil ])
  end
end
