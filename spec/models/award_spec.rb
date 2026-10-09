require "rails_helper"

RSpec.describe HrLite::Award do
  let(:user) { create(:user) }

  it "labels each period and finds the latest started winner of each kind" do
    travel_to(Date.new(2027, 8, 20)) do
      month = described_class.create!(user: user, kind: "month", period_start: Date.new(2027, 8, 9), citation: "a")
      described_class.create!(user: user, kind: "month", period_start: Date.new(2027, 7, 1), citation: "b")
      described_class.create!(user: user, kind: "month", period_start: Date.new(2027, 9, 1), citation: "future")
      quarter = described_class.create!(user: user, kind: "quarter", period_start: Date.new(2027, 8, 1), citation: "c")
      year = described_class.create!(user: user, kind: "year", period_start: Date.new(2027, 3, 3), citation: "d")

      expect([ month, quarter, year ].map(&:period_label)).to eq([ "August 2027", "Q3 2027", "2027" ])
      expect(quarter.period_start).to eq(Date.new(2027, 7, 1))
      expect(described_class.current).to eq([ month, quarter, year ])
    end
  end
end
