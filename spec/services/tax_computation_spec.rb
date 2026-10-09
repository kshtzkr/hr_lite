require "rails_helper"

RSpec.describe HrLite::TaxComputation do
  let(:user) { create(:user) }
  let(:month) { Date.new(2026, 10, 1) }
  let!(:profile) { create(:employee_profile, user: user) }
  let!(:structure) do
    create(:salary_structure, user: user, effective_from: Date.new(2026, 4, 1), basic: 50_000, hra: 20_000,
                              special_allowance: 30_000, metro: true)
  end

  def declaration(regime: "old", **lines)
    HrLite::TaxDeclaration.create!(user_id: user.id, financial_year: Date.new(2026, 4, 1), regime: regime).tap do |d|
      lines.each do |section, (amount, extra)|
        d.tax_declaration_items.create!({ section: section.to_s, declared_amount: amount }.merge(extra || {}))
      end
    end
  end

  it "caps each section by law, doubles 80D for a senior, and works HRA out from the rent" do
    d = declaration("80c": 200_000, "80d": 30_000, "80d_parents": [ 60_000, { senior: true } ],
                    hra: [ 300_000, { landlord_pan: "abcde1234f" } ], other: 10_000)
    rows = d.deduction_rows(structure: structure).index_by(&:section)

    expect(rows.transform_values(&:allowed)).to eq(
      "80c" => 150_000, "80d" => 25_000, "80d_parents" => 50_000, "other" => 10_000,
      # least of HRA received 2,40,000, rent − 10% of Basic 2,40,000, 50% of Basic (metro) 3,00,000
      "hra" => 240_000
    )
    expect(d.old_regime_deductions(structure: structure)).to eq(475_000)
  end

  it "computes both regimes from the year so far, the same way payroll does" do
    declaration("80c": 150_000)
    tax = described_class.new(user: user, on: month)

    expect(tax.months_left).to eq(6)
    expect(tax.sheets["new"].gross).to eq(600_000) # nothing paid yet; ₹1,00,000 × 6 months
    expect(tax.sheets["old"].deductions.map(&:allowed)).to eq([ 150_000 ])
    expect(tax.sheets["new"].slabs.sum { |row| row[:income] }).to eq(tax.sheets["new"].taxable)
    expect(tax.chosen.regime).to eq("old")
    winner, by = tax.saving
    expect(winner).to eq("new")
    expect(by).to eq(tax.sheets["old"].annual_tax - tax.sheets["new"].annual_tax)
    expect(tax.chosen.monthly).to eq(((tax.chosen.annual_tax - tax.chosen.tds_paid) / 6).round)
  end

  it "asks for the landlord's PAN above ₹1 lakh of rent, and takes only PDF or image proofs" do
    d = declaration
    item = d.tax_declaration_items.build(section: "hra", declared_amount: 150_000)
    expect(item).not_to be_valid
    expect(item.errors[:landlord_pan]).to include("is needed when rent is above ₹1,00,000 a year")
    item.landlord_pan = "12345"
    expect(item).not_to be_valid
    item.landlord_pan = "ABCDE1234F"
    item.proofs.attach(io: StringIO.new("MZ"), filename: "x.exe", content_type: "application/x-msdownload")
    expect(item).not_to be_valid
    expect(item.errors[:proofs]).to be_present
  end

  it "shows no HRA exemption without rent or a salary structure" do
    expect(HrLite::TaxDeclaration.hra_exemption(0, structure)).to eq(0)
    expect(HrLite::TaxDeclaration.hra_exemption(100_000, nil)).to eq(0)
  end
end
