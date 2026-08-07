require "rails_helper"

RSpec.describe "TDS projection" do
  let(:rates) { HrLite::StatutoryRateCard.for(Date.new(2026, 4, 1))[:income_tax] }

  describe "months remaining in the financial year" do
    # The Indian FY runs April..March, and the count INCLUDES the run month.
    # The old `15 - month` under-counted every month from April to December,
    # which both under-projected annual income and spread the balance over
    # one month too few.
    {
      4 => 12, 5 => 11, 6 => 10, 7 => 9, 8 => 8, 9 => 7,
      10 => 6, 11 => 5, 12 => 4, 1 => 3, 2 => 2, 3 => 1
    }.each do |month, expected|
      it "counts #{expected} month(s) left from month #{month}" do
        year = month >= 4 ? 2026 : 2027
        run = create(:payroll_run, period_month: Date.new(year, month, 1))
        builder = HrLite::SlipBuilder.new(run, nil, nil, nil, nil, nil)

        expect(builder.send(:months_remaining_in_fy)).to eq(expected)
      end
    end

    it "stops at the exit month for a leaver" do
      run = create(:payroll_run, period_month: Date.new(2026, 4, 1))
      profile = build(:employee_profile, date_of_exit: Date.new(2026, 6, 30))
      builder = HrLite::SlipBuilder.new(run, nil, nil, profile, nil, nil)

      # April, May, June — not the full twelve.
      expect(builder.send(:months_remaining_in_fy)).to eq(3)
    end
  end

  describe "§87A marginal relief (new regime)" do
    def annual_tax_for(taxable_target)
      # Drive `taxable` directly by handing the projector a single-month FY
      # with the standard deduction added back on.
      result = HrLite::Calculators::Tds.call(
        regime: "new",
        structure_monthly_gross: 0,
        gross_earned_this_month: taxable_target + rates["new"][:standard_deduction],
        fy_gross_paid: 0, fy_tds_paid: 0, months_remaining: 1,
        declared_annual_deductions: 0, rates: rates
      )
      result.annual_tax
    end

    it "charges nothing at the rebate cap" do
      expect(annual_tax_for(BigDecimal("1200000"))).to eq(0)
    end

    it "charges no more than the income earned above the cap" do
      # Slab tax at ₹12,10,000 is ₹61,500 before relief. Relief caps it at the
      # ₹10,000 earned above the cliff, +4% cess = ₹10,400.
      expect(annual_tax_for(BigDecimal("1210000"))).to eq(BigDecimal("10400"))
    end

    it "leaves ordinary high incomes on the slab tax" do
      # ₹20,00,000: 4-8L @5% = 20,000; 8-12L @10% = 40,000; 12-16L @15% =
      # 60,000; 16-20L @20% = 80,000 => 200,000 + 4% cess = 208,000.
      expect(annual_tax_for(BigDecimal("2000000"))).to eq(BigDecimal("208000"))
    end

    it "does not apply relief in the old regime, which has none" do
      result = HrLite::Calculators::Tds.call(
        regime: "old",
        structure_monthly_gross: 0,
        gross_earned_this_month: BigDecimal("510000") + rates["old"][:standard_deduction],
        fy_gross_paid: 0, fy_tds_paid: 0, months_remaining: 1,
        declared_annual_deductions: 0, rates: rates
      )
      # 2.5-5L @5% = 12,500; 5-5.1L @20% = 2,000 => 14,500 + 4% cess = 15,080.
      expect(result.annual_tax).to eq(BigDecimal("15080"))
    end
  end
end
