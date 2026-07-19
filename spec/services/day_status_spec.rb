require "rails_helper"

RSpec.describe HrLite::DayStatus do
  let(:user) { create(:user) }
  # July 2027: 1st is a Thursday; 5th a Monday.
  let(:range) { Date.new(2027, 7, 1)..Date.new(2027, 7, 31) }
  let(:monday) { Date.new(2027, 7, 5) }

  around { |example| travel_to(Date.new(2027, 7, 20)) { example.run } }

  subject(:resolver) { described_class.new(user: user, range: range) }

  describe "precedence" do
    it "holiday beats everything, exposing any punch for a 'worked' hint" do
      create(:holiday, date: monday)
      record = create(:attendance_record, :checked_in, user: user, date: monday)
      day = resolver.for(monday)
      expect(day.kind).to eq(:holiday)
      expect(day.record).to eq(record)
    end

    it "weekend beats leave and punch" do
      saturday = Date.new(2027, 7, 3)
      type = create(:leave_type)
      create(:leave_request, :approved, user: user, leave_type: type,
             start_date: Date.new(2027, 7, 2), end_date: monday)
      expect(resolver.for(saturday).kind).to eq(:weekend)
    end

    it "approved full-day leave beats a punch (admin-created residual case)" do
      type = create(:leave_type)
      create(:leave_request, :approved, user: user, leave_type: type,
             start_date: monday, end_date: monday)
      create(:attendance_record, :checked_in, user: user, date: monday)
      expect(resolver.for(monday).kind).to eq(:leave)
    end

    it "half-day leave coexists with the punch" do
      type = create(:leave_type)
      create(:leave_request, :approved, user: user, leave_type: type, half_day: true,
             start_date: monday, end_date: monday)
      record = create(:attendance_record, :checked_in, user: user, date: monday)

      day = resolver.for(monday)
      expect(day.kind).to eq(:half_day_leave)
      expect(day.record).to eq(record)
      expect(day.leave).to be_present
    end

    it "punch kinds, absent and upcoming" do
      create(:attendance_record, :checked_in, user: user, date: monday)
      create(:attendance_record, :checked_in, user: user, date: monday + 1, status: "half_day")

      expect(resolver.for(monday).kind).to eq(:present)
      expect(resolver.for(monday + 1).kind).to eq(:half_day)
      expect(resolver.for(monday + 2).kind).to eq(:absent)     # past working day, no punch
      expect(resolver.for(Date.new(2027, 7, 26)).kind).to eq(:upcoming)
    end

    it "pending leave does not count" do
      type = create(:leave_type)
      create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      expect(resolver.for(monday).kind).to eq(:absent)
    end
  end

  describe "#counts" do
    it "sums kinds over the whole range" do
      create(:attendance_record, :checked_in, user: user, date: monday)
      counts = resolver.counts
      expect(counts[:present]).to eq(1)
      expect(counts.values.sum).to eq(31)
    end
  end
end
