require "rails_helper"

# The point of the whole change: an accountant adds next year's figures on a
# screen, and payroll uses them. No gem release, no deploy.
RSpec.describe "Statutory rate cards over HTTP", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let(:leader) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Boss") }

  before { HrLite::StatutorySeeds.call }

  describe "who may reach it" do
    it "admits the money tier" do
      sign_in owner
      get "/hr/admin/statutory_rate_cards"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FY 2025-26")
    end

    it "turns leadership away — these figures are pay" do
      sign_in leader
      get "/hr/admin/statutory_rate_cards"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "adding a year" do
    before { sign_in owner }

    # A brand-new install with nothing seeded: the form still opens, dated to
    # the financial year we are actually in, with everything blank.
    it "opens on an empty install without a card to copy" do
      HrLite::StatutoryRateCardRecord.delete_all

      get "/hr/admin/statutory_rate_cards/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Copied from")
      expect(response.body).to include(HrLite::FinancialYear.start_for(Date.current).to_s)
    end

    it "offers the newest card's figures pre-filled, dated to the next year" do
      get "/hr/admin/statutory_rate_cards/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copied from FY 2025-26")
      # PF ceiling carried over rather than left blank to be retyped.
      expect(response.body).to include("15000.0")
    end

    it "saves a year, and payroll computes that year on it" do
      card = HrLite::StatutoryRateCardRecord.first

      post "/hr/admin/statutory_rate_cards", params: {
        statutory_rate_card: {
          effective_from: "2027-04-01",
          pf: card.pf.merge("wage_ceiling" => "21000"),
          esi: card.esi,
          income_tax: {
            "new" => card.income_tax["new"].except("slabs").merge(
              "marginal_relief" => "1",
              "slabs" => { "0" => { "from" => "0", "to" => "500000", "rate" => "0" },
                           "1" => { "from" => "500000", "to" => "", "rate" => "0.2" } }
            ),
            "old" => card.income_tax["old"].except("slabs").merge(
              "slabs" => { "0" => { "from" => "0", "to" => "", "rate" => "0.1" } }
            )
          },
          verified_by: "Priya (CA)", verified_on: "2027-04-05"
        }
      }

      expect(response).to redirect_to("/hr/admin/statutory_rate_cards")
      stored = HrLite::StatutoryRateCardRecord.find_by!(effective_from: Date.new(2027, 4, 1))
      expect(stored.to_card[:pf][:wage_ceiling]).to eq(21_000)
      # The open-ended top slab keeps its nil rather than becoming "".
      expect(stored.to_card[:income_tax]["new"][:slabs].last).to eq([ 500_000, nil, BigDecimal("0.2") ])
      expect(stored.to_card[:income_tax]["new"][:marginal_relief]).to be(true)

      # And the lookup now answers from it, with nothing left to warn about.
      june = Date.new(2027, 6, 1)
      expect(HrLite::StatutoryRateCard.for(june)[:pf][:wage_ceiling]).to eq(21_000)
      expect(HrLite::StatutoryRateCard.warning_for(june)).to be_nil
      expect(HrLite::StatutoryRateCard.unverified_for(june)).to be_nil
    end

    it "leaves an earlier year computing on its own card" do
      card = HrLite::StatutoryRateCardRecord.first
      post "/hr/admin/statutory_rate_cards", params: {
        statutory_rate_card: { effective_from: "2027-04-01",
                               pf: card.pf.merge("wage_ceiling" => "21000"),
                               esi: card.esi, income_tax: card.income_tax }
      }

      expect(HrLite::StatutoryRateCard.for(Date.new(2026, 6, 1))[:pf][:wage_ceiling]).to eq(15_000)
      expect(HrLite::StatutoryRateCard.for(Date.new(2027, 6, 1))[:pf][:wage_ceiling]).to eq(21_000)
    end

    it "refuses a regime posted with no slabs at all" do
      card = HrLite::StatutoryRateCardRecord.first
      post "/hr/admin/statutory_rate_cards", params: {
        statutory_rate_card: {
          effective_from: "2027-04-01", pf: card.pf, esi: card.esi,
          income_tax: { "new" => card.income_tax["new"].except("slabs"),
                        "old" => card.income_tax["old"] }
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(HrLite::StatutoryRateCardRecord.count).to eq(1)
    end

    it "re-renders a mid-year date rather than accepting it" do
      card = HrLite::StatutoryRateCardRecord.first
      post "/hr/admin/statutory_rate_cards", params: {
        statutory_rate_card: { effective_from: "2027-07-01", pf: card.pf,
                               esi: card.esi, income_tax: card.income_tax }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("1 April")
    end
  end

  describe "signing a card off" do
    before { sign_in owner }

    it "records who checked it, and the run stops asking" do
      card = HrLite::StatutoryRateCardRecord.first
      june = Date.new(2025, 6, 1)
      expect(HrLite::StatutoryRateCard.unverified_for(june)).to be_present

      get "/hr/admin/statutory_rate_cards/#{card.id}/edit"
      expect(response).to have_http_status(:ok)

      patch "/hr/admin/statutory_rate_cards/#{card.id}", params: {
        statutory_rate_card: { effective_from: card.effective_from.to_s, pf: card.pf,
                               esi: card.esi, income_tax: card.income_tax,
                               verified_by: "Priya (CA)", verified_on: "2025-04-05" }
      }

      expect(response).to redirect_to("/hr/admin/statutory_rate_cards")
      expect(card.reload).to be_verified
      expect(HrLite::StatutoryRateCard.unverified_for(june)).to be_nil
    end

    it "re-renders an invalid edit" do
      card = HrLite::StatutoryRateCardRecord.first
      patch "/hr/admin/statutory_rate_cards/#{card.id}", params: {
        statutory_rate_card: { effective_from: "2027-09-01", pf: card.pf,
                               esi: card.esi, income_tax: card.income_tax }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the professional-tax summary" do
    it "names the states that are configured" do
      sign_in owner
      get "/hr/admin/statutory_rate_cards"

      expect(response.body).to include("Karnataka")
    end

    it "says plainly when nothing is configured" do
      HrLite::ProfessionalTaxSlab.delete_all
      sign_in owner
      get "/hr/admin/statutory_rate_cards"

      expect(response.body).to include("deducted at ₹0")
    end
  end
end
