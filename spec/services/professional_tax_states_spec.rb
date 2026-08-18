require "rails_helper"

# PT is a state levy, and only Karnataka ever had bands in code. Every other
# state computed ₹0 and said nothing — a wrong answer delivered confidently,
# which is worse than an error.
RSpec.describe HrLite::Calculators::ProfessionalTax do
  let(:june) { Date.new(2027, 6, 1) }
  let(:february) { Date.new(2027, 2, 1) }

  def slab(state:, from:, monthly:, feb_extra: nil, effective_from: Date.new(2025, 4, 1))
    HrLite::ProfessionalTaxSlab.create!(state: state, effective_from: effective_from,
                                        from_amount: from, monthly: monthly, feb_extra: feb_extra)
  end

  def pt(state, gross, month = june)
    described_class.call(state: state, gross_earned: gross, period_month: month)
  end

  describe "a state with stored bands" do
    before do
      slab(state: "maharashtra", from: 7_500, monthly: 175)
      slab(state: "maharashtra", from: 10_000, monthly: 200, feb_extra: 300)
    end

    it "picks the highest band the earnings clear" do
      expect(pt("maharashtra", 6_000)).to eq(0)
      expect(pt("maharashtra", 7_500)).to eq(175)
      expect(pt("maharashtra", 9_999)).to eq(175)
      expect(pt("maharashtra", 25_000)).to eq(200)
    end

    it "adds the February top-up only in February" do
      expect(pt("maharashtra", 25_000, february)).to eq(500)
      expect(pt("maharashtra", 25_000, june)).to eq(200)
      # The lower band carries no top-up, so February changes nothing there.
      expect(pt("maharashtra", 8_000, february)).to eq(175)
    end

    it "treats the lower bound as inclusive" do
      # `above: 24999` with a strict `>` used to tax a prorated ₹24,999.50 as
      # if it were below the threshold.
      slab(state: "karnataka", from: 25_000, monthly: 200)
      expect(pt("karnataka", BigDecimal("24999.50"))).to eq(0)
      expect(pt("karnataka", BigDecimal("25000"))).to eq(200)
    end
  end

  describe "dating" do
    it "uses the bands in force for the run's month, not today's" do
      slab(state: "telangana", from: 20_000, monthly: 200, effective_from: Date.new(2025, 4, 1))
      slab(state: "telangana", from: 20_000, monthly: 250, effective_from: Date.new(2027, 4, 1))

      expect(pt("telangana", 30_000, Date.new(2026, 6, 1))).to eq(200)
      expect(pt("telangana", 30_000, Date.new(2027, 6, 1))).to eq(250)
    end

    it "ignores bands that had not taken effect yet" do
      slab(state: "telangana", from: 20_000, monthly: 250, effective_from: Date.new(2030, 4, 1))
      expect(pt("telangana", 30_000)).to eq(0)
    end
  end

  describe "a state nobody has configured" do
    it "deducts nothing, but says it is unconfigured" do
      expect(pt("gujarat", 50_000)).to eq(0)
      expect(described_class).to be_unconfigured("gujarat", june)
    end

    # "none" is a decision somebody made, not silence.
    it "does not flag the explicit no-levy state" do
      expect(described_class).not_to be_unconfigured(HrLite::ProfessionalTaxSlab::NO_LEVY, june)
    end

    it "stops flagging a state once its bands are entered" do
      slab(state: "gujarat", from: 12_000, monthly: 200)
      expect(described_class).not_to be_unconfigured("gujarat", june)
    end
  end

  # Gem upgraded, `db:migrate` not yet run. Payroll must fall back to the
  # figures the gem ships rather than 500 on a missing table.
  describe "a host that has not migrated yet" do
    it "falls back to the caller's own slab table" do
      allow(HrLite::ProfessionalTaxSlab).to receive(:table_for)
        .and_raise(ActiveRecord::StatementInvalid, "no such table")

      rates = { "karnataka" => [ { from: BigDecimal("25000"), monthly: BigDecimal("200") } ] }
      amount = described_class.call(state: "karnataka", gross_earned: 30_000,
                                    period_month: june, rates: rates)

      expect(amount).to eq(200)
    end
  end

  describe "the payroll run" do
    around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

    it "warns once per unconfigured state, not once per employee" do
      leader = create(:user)
      2.times do
        profile = create(:employee_profile)
        create(:salary_structure, user: profile.user, pt_state: "gujarat")
      end
      run = create(:payroll_run, period_month: june)

      run.compute!(actor: leader)

      matching = run.warnings.grep(/professional-tax slabs/)
      expect(matching.size).to eq(1)
      expect(matching.first).to include("Gujarat", "₹0")
    end

    it "says nothing when the state is configured" do
      slab(state: "gujarat", from: 12_000, monthly: 200)
      leader = create(:user)
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user, pt_state: "gujarat")
      run = create(:payroll_run, period_month: june)

      run.compute!(actor: leader)

      expect(run.warnings.grep(/professional-tax slabs/)).to be_empty
    end
  end
end
