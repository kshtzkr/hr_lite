require "rails_helper"

RSpec.describe "Payroll calculators" do
  let(:rates) { HrLite::StatutoryRateCard.for(Date.new(2027, 6, 1)) }

  describe HrLite::Calculators::Proration do
    let(:structure) do
      build(:salary_structure, basic: BigDecimal("40000"), hra: BigDecimal("20000"),
                               special_allowance: BigDecimal("15000"), other_earnings: nil)
    end

    it "pays the full month untouched" do
      rows = described_class.call(structure: structure, payable_days: 30, days_in_month: 30)
      expect(rows.map { |r| r[:amount] }).to eq([ 40000, 20000, 15000 ].map { |v| BigDecimal(v) })
      expect(rows.map { |r| r[:code] }).to eq(%w[basic hra special_allowance])
    end

    it "prorates by payable/days at paise precision" do
      rows = described_class.call(structure: structure, payable_days: BigDecimal("27.5"), days_in_month: 30)
      expect(rows.find { |r| r[:code] == "basic" }[:amount]).to eq(BigDecimal("36666.67"))
    end

    it "handles zero payable days and skips nil/zero components" do
      rows = described_class.call(structure: structure, payable_days: 0, days_in_month: 30)
      expect(rows.map { |r| r[:amount] }).to all(eq(0))
      expect(rows.map { |r| r[:code] }).not_to include("other_earnings")
    end
  end

  describe HrLite::Calculators::Pf do
    it "caps the wage at the ceiling by default" do
      result = described_class.call(basic_earned: BigDecimal("40000"), on_full_basic: false, rates: rates[:pf])
      expect(result.pf_wage).to eq(15000)
      expect(result.employee).to eq(1800)
      expect(result.employer_eps).to eq(1250)   # 8.33% of 15000 = 1249.5 -> 1250 (half-up)
      expect(result.employer_epf).to eq(550)    # 1800 - 1250
      expect(result.edli).to eq(75)
      expect(result.admin_charges).to eq(75)
    end

    it "uses full basic when opted in, EPS still wage-capped" do
      result = described_class.call(basic_earned: BigDecimal("40000"), on_full_basic: true, rates: rates[:pf])
      expect(result.pf_wage).to eq(40000)
      expect(result.employee).to eq(4800)
      expect(result.employer_eps).to eq(1250)   # EPS wage stays capped at 15000
      expect(result.employer_epf).to eq(3550)
    end

    it "works below the ceiling (LOP-reduced basic)" do
      result = described_class.call(basic_earned: BigDecimal("12000"), on_full_basic: false, rates: rates[:pf])
      expect(result.pf_wage).to eq(12000)
      expect(result.employee).to eq(1440)
      expect(result.employer_eps).to eq(1000)   # 999.6 -> 1000
      expect(result.employer_epf).to eq(440)
    end
  end

  describe HrLite::Calculators::Esi do
    it "is exempt above the gross ceiling regardless of earned gross" do
      result = described_class.call(monthly_gross: BigDecimal("75000"), gross_earned: BigDecimal("15000"),
                                    applicable: true, rates: rates[:esi])
      expect(result.applicable?).to be(false)
      expect(result.employee).to eq(0)
    end

    it "contributes on earned gross with ceil rounding at/below the ceiling" do
      result = described_class.call(monthly_gross: BigDecimal("21000"), gross_earned: BigDecimal("20001"),
                                    applicable: true, rates: rates[:esi])
      expect(result.applicable?).to be(true)
      expect(result.employee).to eq(151)  # 150.0075 -> 151 (ceil)
      expect(result.employer).to eq(651)  # 650.0325 -> 651
    end

    it "honours the structure opt-out flag" do
      result = described_class.call(monthly_gross: BigDecimal("18000"), gross_earned: BigDecimal("18000"),
                                    applicable: false, rates: rates[:esi])
      expect(result.applicable?).to be(false)
    end
  end

  describe HrLite::Calculators::ProfessionalTax do
    it "returns zero for none/unknown/PT-free states" do
      %w[none uttar_pradesh uttarakhand narnia].each do |state|
        expect(described_class.call(state: state, gross_earned: BigDecimal("50000"),
                                    period_month: Date.new(2027, 6, 1), rates: rates[:pt])).to eq(0)
      end
    end

    it "applies the slab when gross clears it" do
      expect(described_class.call(state: "karnataka", gross_earned: BigDecimal("30000"),
                                  period_month: Date.new(2027, 6, 1), rates: rates[:pt])).to eq(200)
      expect(described_class.call(state: "karnataka", gross_earned: BigDecimal("20000"),
                                  period_month: Date.new(2027, 6, 1), rates: rates[:pt])).to eq(0)
    end

    it "adds feb_extra in February when configured" do
      custom = { "maha_like" => [ { above: BigDecimal("10000"), monthly: BigDecimal("200"),
                                    feb_extra: BigDecimal("100") } ] }
      expect(described_class.call(state: "maha_like", gross_earned: BigDecimal("30000"),
                                  period_month: Date.new(2027, 2, 1), rates: custom)).to eq(300)
      expect(described_class.call(state: "maha_like", gross_earned: BigDecimal("30000"),
                                  period_month: Date.new(2027, 3, 1), rates: custom)).to eq(200)
    end
  end

  describe HrLite::Calculators::Tds do
    let(:tax_rates) { rates[:income_tax] }

    def tds(**kw)
      defaults = {
        regime: "new", structure_monthly_gross: BigDecimal("100000"),
        gross_earned_this_month: BigDecimal("100000"), fy_gross_paid: BigDecimal("0"),
        fy_tds_paid: BigDecimal("0"), months_remaining: 12,
        declared_annual_deductions: nil, rates: tax_rates
      }
      described_class.call(**defaults.merge(kw))
    end

    it "gives zero tax under the 87A rebate cap (12L gross ≈ 11.25L taxable)" do
      result = tds(structure_monthly_gross: BigDecimal("100000"), gross_earned_this_month: BigDecimal("100000"))
      expect(result.taxable).to eq(BigDecimal("1125000"))
      expect(result.annual_tax).to eq(0)
      expect(result.monthly).to eq(0)
    end

    it "computes slab tax + cess above the rebate cap" do
      # 24L annual gross, 75k standard deduction -> 23.25L taxable
      # slabs: 4L@0 + 4L@5% (20000) + 4L@10% (40000) + 4L@15% (60000) + 4L@20% (80000) + 3.25L@25% (81250)
      # = 281250; +4% cess = 292500 -> §288B stays 292500; monthly = 24375
      result = tds(structure_monthly_gross: BigDecimal("200000"), gross_earned_this_month: BigDecimal("200000"))
      expect(result.taxable).to eq(BigDecimal("2325000"))
      expect(result.annual_tax).to eq(BigDecimal("292500"))
      expect(result.monthly).to eq(24375)
    end

    it "credits TDS already deducted and spreads over remaining months" do
      result = tds(structure_monthly_gross: BigDecimal("200000"), gross_earned_this_month: BigDecimal("200000"),
                   fy_gross_paid: BigDecimal("600000"), fy_tds_paid: BigDecimal("80000"), months_remaining: 9)
      # projected = 600000 + 200000 + 200000*8 = 2400000 -> same annual 292500
      expect(result.annual_tax).to eq(BigDecimal("292500"))
      expect(result.monthly).to eq(HrLite::Money.round_rupee((BigDecimal("212500")) / 9))
    end

    it "clamps negative monthly to zero (over-deducted earlier)" do
      result = tds(structure_monthly_gross: BigDecimal("50000"), gross_earned_this_month: BigDecimal("50000"),
                   fy_tds_paid: BigDecimal("999999"), months_remaining: 3)
      expect(result.monthly).to eq(0)
    end

    it "old regime: smaller standard deduction plus declared deductions" do
      result = tds(regime: "old", structure_monthly_gross: BigDecimal("100000"),
                   gross_earned_this_month: BigDecimal("100000"),
                   declared_annual_deductions: BigDecimal("150000"))
      expect(result.taxable).to eq(BigDecimal("1000000")) # 12L - 50k - 1.5L
      # old slabs: 2.5L@0 + 2.5L@5% (12500) + 5L@20% (100000) = 112500; cess -> 117000
      expect(result.annual_tax).to eq(BigDecimal("117000"))
    end

    it "ignores declared deductions in the new regime" do
      with = tds(declared_annual_deductions: BigDecimal("150000"))
      without = tds(declared_annual_deductions: nil)
      expect(with.taxable).to eq(without.taxable)
    end

    it "override short-circuits everything" do
      result = tds(override: BigDecimal("12345"))
      expect(result.monthly).to eq(12345)
      expect(result.details["override"]).to eq("12345.0")
      expect(result.taxable).to be_nil
    end

    it "flags high incomes for manual review" do
      result = tds(structure_monthly_gross: BigDecimal("500000"), gross_earned_this_month: BigDecimal("500000"))
      expect(result.details["high_income_review"]).to eq("true")
    end

    it "guards months_remaining floor at 1" do
      result = tds(months_remaining: 0)
      expect(result.monthly).to be >= 0
    end
  end
end
