require "rails_helper"

RSpec.describe HrLite::LeaveDayCounter do
  # Mon 5 Jul 2027 .. Fri 9 Jul 2027
  it "counts working days across a range, skipping weekend and holidays" do
    create(:holiday, date: Date.new(2027, 7, 7))
    days = described_class.count_range(start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 11))
    expect(days).to eq(4) # Mon Tue Thu Fri (Wed holiday, Sat Sun weekend)
  end

  it "returns 0.5 for a half-day on a working day" do
    days = described_class.count_range(start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 5), half_day: true)
    expect(days).to eq(BigDecimal("0.5"))
  end

  it "returns 0 for a half-day on a weekend" do
    days = described_class.count_range(start_date: Date.new(2027, 7, 4), end_date: Date.new(2027, 7, 4), half_day: true)
    expect(days).to eq(0)
  end

  it "handles nil and inverted ranges" do
    expect(described_class.count_range(start_date: nil, end_date: Date.current)).to eq(0)
    expect(described_class.count_range(start_date: Date.current, end_date: Date.current - 3)).to eq(0)
  end

  it "counts via a request object" do
    request = build(:leave_request, start_date: Date.new(2027, 7, 5), end_date: Date.new(2027, 7, 6))
    expect(described_class.count(request)).to eq(2)
  end
end
