require "rails_helper"

RSpec.describe "Statutory figures as data" do
  let(:month) { Date.new(2027, 6, 1) }

  def seed!
    HrLite::StatutorySeeds.call
  end

  describe HrLite::StatutorySeeds do
    it "copies the shipped figures in without changing a single number" do
      seed!
      shipped = HrLite::StatutoryRateCard::CARDS[Date.new(2025, 4, 1)]
      stored = HrLite::StatutoryRateCardRecord.find_by!(effective_from: Date.new(2025, 4, 1)).to_card

      expect(stored[:pf]).to eq(shipped[:pf])
      expect(stored[:esi]).to eq(shipped[:esi])
      expect(stored[:income_tax]["new"][:slabs]).to eq(shipped[:income_tax]["new"][:slabs])
      expect(stored[:income_tax]["old"][:standard_deduction])
        .to eq(shipped[:income_tax]["old"][:standard_deduction])
    end

    it "keeps every figure a BigDecimal through the JSON round trip" do
      seed!
      card = HrLite::StatutoryRateCardRecord.first.to_card

      expect(card[:pf][:wage_ceiling]).to be_a(BigDecimal)
      expect(card[:income_tax]["new"][:slabs].flatten.compact).to all(be_a(BigDecimal))
      expect(card[:pf][:employee_rate]).to eq(BigDecimal("0.12"))
    end

    it "never puts the gem's numbers back over a corrected card" do
      seed!
      card = HrLite::StatutoryRateCardRecord.first
      card.update!(pf: card.pf.merge("wage_ceiling" => "21000.0"), verified_by: "CA")

      expect(seed!).to be_empty
      expect(card.reload.to_card[:pf][:wage_ceiling]).to eq(21_000)
    end

    it "copies Karnataka's bands and invents none for the states with no data" do
      seed!

      expect(HrLite::ProfessionalTaxSlab.for_state("karnataka").count).to eq(1)
      expect(HrLite::ProfessionalTaxSlab.for_state("uttar_pradesh")).to be_empty
    end
  end

  describe HrLite::StatutoryRateCard, "reading the table" do
    it "prefers a stored card over the shipped hash" do
      seed!
      HrLite::StatutoryRateCardRecord.create!(
        effective_from: Date.new(2027, 4, 1),
        pf: HrLite::StatutoryRateCardRecord.first.pf.merge("wage_ceiling" => "21000.0"),
        esi: HrLite::StatutoryRateCardRecord.first.esi,
        income_tax: HrLite::StatutoryRateCardRecord.first.income_tax,
        verified_by: "Priya (CA)", verified_on: Date.new(2027, 4, 5)
      )

      expect(described_class.for(month)[:pf][:wage_ceiling]).to eq(21_000)
      expect(described_class).not_to be_stale_for(month)
      expect(described_class.warning_for(month)).to be_nil
    end

    it "falls back to the shipped hash when nothing is stored" do
      expect(HrLite::StatutoryRateCardRecord.count).to eq(0)
      expect(described_class.for(month)[:pf][:wage_ceiling]).to eq(15_000)
    end

    # Gem upgraded, `db:migrate` not yet run. Payroll falls back to the
    # shipped figures rather than 500 on a missing table.
    it "falls back when the table is not there at all" do
      allow(HrLite::StatutoryRateCardRecord).to receive(:table_exists?)
        .and_raise(ActiveRecord::StatementInvalid, "no such table")

      expect(described_class.for(month)[:pf][:wage_ceiling]).to eq(15_000)
      expect(described_class.earliest_date).to eq(Date.new(2025, 4, 1))
    end

    it "still warns when the newest stored card is a year behind" do
      seed! # newest stored card is FY 2025-26; the run is FY 2027-28
      expect(described_class).to be_stale_for(month)
      expect(described_class.warning_for(month)).to include("FY 2027-28")
    end

    it "says when a card for the right year has not been signed off" do
      seed!
      HrLite::StatutoryRateCardRecord.create!(
        effective_from: Date.new(2027, 4, 1),
        pf: HrLite::StatutoryRateCardRecord.first.pf,
        esi: HrLite::StatutoryRateCardRecord.first.esi,
        income_tax: HrLite::StatutoryRateCardRecord.first.income_tax
      )

      expect(described_class.unverified_for(month)).to include("has not been marked verified")
    end

    it "says nothing about verification once somebody has signed it off" do
      seed!
      HrLite::StatutoryRateCardRecord.first.update!(verified_by: "Priya (CA)",
                                                    verified_on: Date.current)

      expect(described_class.unverified_for(Date.new(2025, 6, 1))).to be_nil
    end

    # Wrong-year figures are the worse problem; do not bury it under a second
    # sentence about paperwork.
    it "does not add the verification note on top of a staleness warning" do
      seed!
      expect(described_class.unverified_for(month)).to be_nil
    end
  end

  describe HrLite::StatutoryRateCardRecord, "validation" do
    let(:valid) do
      HrLite::StatutorySeeds.call
      described_class.first
    end

    it "refuses a card dated mid-year" do
      record = described_class.new(effective_from: Date.new(2027, 7, 1),
                                   pf: valid.pf, esi: valid.esi, income_tax: valid.income_tax)

      expect(record).not_to be_valid
      expect(record.errors[:effective_from].join).to include("1 April")
    end

    # A card missing a figure does not fail at save time; it fails half way
    # through computing somebody's salary, as a NoMethodError on nil.
    it "refuses a card missing a figure payroll reads" do
      record = described_class.new(effective_from: Date.new(2027, 4, 1),
                                   pf: valid.pf.except("eps_rate"),
                                   esi: valid.esi, income_tax: valid.income_tax)

      expect(record).not_to be_valid
      expect(record.errors[:pf].join).to include("eps_rate")
    end

    it "refuses a card missing a whole tax regime" do
      record = described_class.new(effective_from: Date.new(2027, 4, 1),
                                   pf: valid.pf, esi: valid.esi,
                                   income_tax: valid.income_tax.except("old"))

      expect(record).not_to be_valid
      expect(record.errors[:income_tax].join).to include("old regime")
    end

    it "reports a card with no sign-off date as unverified" do
      valid.update_columns(verified_by: "Priya", verified_on: nil)
      expect(valid.reload).not_to be_verified
    end

    it "refuses two cards for one date" do
      duplicate = described_class.new(effective_from: valid.effective_from,
                                      pf: valid.pf, esi: valid.esi, income_tax: valid.income_tax)
      expect(duplicate).not_to be_valid
    end
  end
end
