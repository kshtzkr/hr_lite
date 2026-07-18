require "rails_helper"

RSpec.describe HrLite::DayStatus do
  let(:user) { create(:user) }
  let(:range) { Date.current.beginning_of_month..Date.current.end_of_month }
  subject(:resolver) { described_class.new(user: user, range: range) }

  it "classifies punched days by their status" do
    create(:attendance_record, :checked_in, user: user, date: Date.current)
    expect(resolver.for(Date.current).kind).to eq(:present)
  end

  it "reports half days" do
    create(:attendance_record, :checked_in, user: user, date: Date.current, status: "half_day")
    expect(resolver.for(Date.current).kind).to eq(:half_day)
  end

  it "marks past days without a check-in absent (even with an empty record)" do
    create(:attendance_record, user: user, date: Date.current - 1)
    expect(resolver.for(Date.current - 1).kind).to eq(:absent)
  end

  it "marks future days upcoming" do
    expect(resolver.for(Date.current + 1).kind).to eq(:upcoming) if Date.current + 1 <= range.last
  end

  it "exposes the record for tooltips" do
    record = create(:attendance_record, :checked_out, user: user, date: Date.current)
    expect(resolver.for(Date.current).record).to eq(record)
  end

  it "counts kinds across the range" do
    create(:attendance_record, :checked_in, user: user, date: Date.current)
    counts = resolver.counts
    expect(counts[:present]).to eq(1)
    expect(counts.values.sum).to eq(range.count)
  end
end
