require "rails_helper"

RSpec.describe HrLite::LeaveBalance, "leave-year accrual and joining proration" do
  let(:user) { create(:user, name: "Naya") }
  # Keka-style rates: SL 12/yr = 1/month, CL 18/yr = 1.5/month.
  let(:sick) { create(:leave_type, :monthly, code: "SL2", name: "Sick", annual_quota: 12) }
  let(:casual) { create(:leave_type, :monthly, code: "CL2", name: "Casual", annual_quota: 18) }
  let(:upfront) { create(:leave_type, code: "OH2", name: "Optional", annual_quota: 2) }

  def balance(type, year)
    described_class.for(user, type, year)
  end

  describe "July–June leave year" do
    before { HrLite.config.leave_year_start_month = 7 }

    it "credits monthly from July: 1/month sick, 1.5/month casual" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
      travel_to(Date.new(2026, 9, 20)) do # 3rd month of the 2026–27 year
        expect(balance(sick, 2026).entitled).to eq(3.0)
        expect(balance(casual, 2026).entitled).to eq(4.5)
      end
      travel_to(Date.new(2027, 6, 30)) do # 12th month
        expect(balance(sick, 2026).entitled).to eq(12.0)
        expect(balance(casual, 2026).entitled).to eq(18.0)
      end
    end

    it "prorates a mid-year joiner from their joining month" do
      # Joined 10 Oct (on/before the 15th -> October counts).
      create(:employee_profile, user: user, date_of_joining: Date.new(2026, 10, 10))
      travel_to(Date.new(2026, 12, 31)) do
        expect(balance(sick, 2026).entitled).to eq(3.0)   # Oct Nov Dec
        expect(balance(casual, 2026).entitled).to eq(4.5)
      end
    end

    it "starts from the NEXT month when they join after the 15th" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2026, 10, 20))
      travel_to(Date.new(2026, 12, 31)) do
        expect(balance(sick, 2026).entitled).to eq(2.0)   # Nov Dec
      end
    end

    it "prorates yearly-upfront grants by remaining months" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2027, 1, 5))
      # Jan..Jun = 6 of 12 months -> 2 * 6/12 = 1.0
      travel_to(Date.new(2027, 2, 1)) do
        expect(balance(upfront, 2026).entitled).to eq(1.0)
      end
    end

    it "gives nothing for a leave year that ends before they join" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2027, 8, 1))
      expect(balance(sick, 2026).entitled).to eq(0)
    end

    it "windows `used` on the leave year, not the calendar year" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
      travel_to(Date.new(2027, 2, 1)) do
        # Feb 2027 sits inside leave year 2026.
        request = create(:leave_request, user: user, leave_type: sick,
                         start_date: Date.new(2027, 2, 2), end_date: Date.new(2027, 2, 2))
        request.update!(status: "approved")
        expect(balance(sick, 2026).used).to eq(1)
        expect(balance(sick, 2027).used).to eq(0)
      end
    end

    it "keys requests to the leave year and blocks cross-boundary spans" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
      travel_to(Date.new(2027, 6, 15)) do
        request = build(:leave_request, user: user, leave_type: sick,
                        start_date: Date.new(2027, 6, 30), end_date: Date.new(2027, 7, 1))
        expect(request).not_to be_valid
        expect(request.errors[:base].join).to include("leave-year boundary")

        june = build(:leave_request, user: user, leave_type: sick,
                     start_date: Date.new(2027, 6, 29), end_date: Date.new(2027, 6, 29))
        expect(june.balance.year).to eq(2026)
      end
    end

    it "rolls carry into the new July year and credits comp-off into the current leave year" do
      co = create(:leave_type, :comp_off, code: "CO2", name: "Comp off 2", carry_forward_cap: 5)
      create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
      admin = create(:user, admin: true)

      travel_to(Date.new(2027, 6, 20)) do
        balance(co, 2026).tap { |b| b.adjustment = 3; b.save! }
      end
      travel_to(Date.new(2027, 7, 1)) do
        HrLite::LeaveYearRolloverJob.perform_now
        expect(balance(co, 2027).carried_forward).to eq(3)

        # Worked the last Sunday of the OLD leave year; approved after
        # rollover -> credit lands in the new year (2027), spendable now.
        request = create(:comp_off_request, user: user, date_worked: Date.new(2027, 6, 27),
                         reason: "June departures")
        request.approve!(actor: admin)
        expect(balance(co, 2027).reload.adjustment).to eq(1)
      end
    end
  end

  it "keeps calendar-year behaviour identical by default" do
    create(:employee_profile, user: user, date_of_joining: Date.new(2025, 1, 1))
    travel_to(Date.new(2027, 7, 10)) do
      expect(balance(sick, 2027).entitled).to eq(7.0)
      expect(balance(upfront, 2027).entitled).to eq(2.0)
    end
  end
end
