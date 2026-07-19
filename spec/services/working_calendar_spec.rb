require "rails_helper"

RSpec.describe HrLite::WorkingCalendar do
  # July 2027: 1st = Thursday. 5 Saturdays (3,10,17,24,31), 4 Sundays.
  let(:range) { Date.new(2027, 7, 1)..Date.new(2027, 7, 31) }

  def calendar
    described_class.new(range)
  end

  describe "weekend policies" do
    it "sat_sun (default): both weekend days off" do
      cal = calendar
      expect(cal.weekend?(Date.new(2027, 7, 3))).to be(true)   # Sat
      expect(cal.weekend?(Date.new(2027, 7, 4))).to be(true)   # Sun
      expect(cal.weekend?(Date.new(2027, 7, 5))).to be(false)  # Mon
    end

    it "sun_only: Saturdays are working days" do
      HrLite::Setting.instance.update!(weekend_policy: "sun_only")
      cal = calendar
      expect(cal.weekend?(Date.new(2027, 7, 3))).to be(false)
      expect(cal.weekend?(Date.new(2027, 7, 4))).to be(true)
    end

    it "second_fourth_sat_sun: only the 2nd and 4th Saturdays off" do
      HrLite::Setting.instance.update!(weekend_policy: "second_fourth_sat_sun")
      cal = calendar
      expect(cal.weekend?(Date.new(2027, 7, 3))).to be(false)   # 1st Sat
      expect(cal.weekend?(Date.new(2027, 7, 10))).to be(true)   # 2nd Sat
      expect(cal.weekend?(Date.new(2027, 7, 17))).to be(false)  # 3rd Sat
      expect(cal.weekend?(Date.new(2027, 7, 24))).to be(true)   # 4th Sat
      expect(cal.weekend?(Date.new(2027, 7, 31))).to be(false)  # 5th Sat
      expect(cal.weekend?(Date.new(2027, 7, 11))).to be(true)   # Sunday
    end
  end

  describe "holidays" do
    it "counts only company-wide holidays" do
      create(:holiday, date: Date.new(2027, 7, 5), name: "Founders day")
      create(:holiday, :optional, date: Date.new(2027, 7, 6), name: "Optional fest")
      cal = calendar

      expect(cal.holiday?(Date.new(2027, 7, 5))).to be(true)
      expect(cal.holiday?(Date.new(2027, 7, 6))).to be(false)
      expect(cal.working_day?(Date.new(2027, 7, 5))).to be(false)
      expect(cal.working_day?(Date.new(2027, 7, 6))).to be(true)
    end
  end

  describe "#working_days_in" do
    it "excludes weekends and holidays" do
      create(:holiday, date: Date.new(2027, 7, 5))
      # July 2027: 31 days, 9 weekend days (5 Sat + 4 Sun), 1 holiday (Mon 5th).
      expect(calendar.working_days_in(range)).to eq(21)
    end
  end
end
