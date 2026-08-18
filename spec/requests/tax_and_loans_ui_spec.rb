require "rails_helper"

# TaxDeclaration and Loan shipped in 0.13/0.14 with models, tables and
# payroll integration but no screen. Loans at least reached a payslip;
# declarations were a table nobody could file into.
RSpec.describe "Tax declarations over HTTP", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Farid") }
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN) }

  describe "an employee filing one" do
    before { sign_in employee }

    it "opens a blank declaration with a line per section" do
      get "/hr/tax_declaration"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("80C", "80D", "NPS", "HRA")
    end

    it "saves a draft and totals what was claimed" do
      patch "/hr/tax_declaration", params: {
        tax_declaration: {
          regime: "old",
          tax_declaration_items_attributes: {
            "0" => { section: "80c", declared_amount: "150000", label: "ELSS" },
            "1" => { section: "80d", declared_amount: "25000", label: "Health cover" }
          }
        }
      }

      declaration = HrLite::TaxDeclaration.find_by!(user_id: employee.id)
      expect(declaration.regime).to eq("old")
      expect(declaration.declared_total).to eq(175_000)
      expect(declaration).to be_draft
    end

    it "submits, and cannot be edited once verified" do
      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "old", tax_declaration_items_attributes: {
          "0" => { section: "80c", declared_amount: "100000" }
        } }
      }
      post "/hr/tax_declaration/submit"
      declaration = HrLite::TaxDeclaration.find_by!(user_id: employee.id)
      expect(declaration).to be_submitted

      declaration.verify!(actor: finance)
      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "new", tax_declaration_items_attributes: {} }
      }

      expect(flash[:alert]).to include("verified")
      expect(declaration.reload.regime).to eq("old")
    end

    # A real browser posts a line for EVERY section, not just the ones filled
    # in. Specs that post only what they set never see this; the form 500s.
    it "ignores the blank sections a real form always posts" do
      all_sections = HrLite::TaxDeclarationItem::SECTIONS.each_with_index.to_h { |section, i|
        [ i.to_s, { section: section, label: "", declared_amount: section == "80c" ? "150000" : "" } ]
      }

      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "old", tax_declaration_items_attributes: all_sections }
      }

      expect(response).to have_http_status(:redirect)
      declaration = HrLite::TaxDeclaration.find_by!(user_id: employee.id)
      expect(declaration.tax_declaration_items.count).to eq(1)
      expect(declaration.declared_total).to eq(150_000)
    end

    it "withdraws a claim when its amount is cleared" do
      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "old", tax_declaration_items_attributes: {
          "0" => { section: "80c", declared_amount: "150000" }
        } }
      }
      declaration = HrLite::TaxDeclaration.find_by!(user_id: employee.id)
      item = declaration.tax_declaration_items.first

      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "old", tax_declaration_items_attributes: {
          "0" => { id: item.id, section: "80c", declared_amount: "" }
        } }
      }

      expect(declaration.reload.tax_declaration_items.count).to eq(0)
      expect(declaration.declared_total).to eq(0)
    end

    it "falls back to this financial year when the param is nonsense" do
      get "/hr/tax_declaration?financial_year=not-a-date"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FY #{HrLite::FinancialYear.label(Date.current)}")
    end

    it "says so when there is nothing to submit" do
      post "/hr/tax_declaration/submit"
      expect(flash[:alert]).to include("Nothing to submit")
    end

    it "cannot submit twice" do
      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "old", tax_declaration_items_attributes: {
          "0" => { section: "80c", declared_amount: "1000" }
        } }
      }
      post "/hr/tax_declaration/submit"
      post "/hr/tax_declaration/submit"

      expect(flash[:alert]).to include("Only a draft")
    end

    it "re-renders an invalid save with every section still on the form" do
      patch "/hr/tax_declaration", params: {
        tax_declaration: { regime: "sideways", tax_declaration_items_attributes: {
          "0" => { section: "80c", declared_amount: "1000" }
        } }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("80D")
    end

    it "never shows somebody else's" do
      other = user_with_roles(HrLite::Role::EMPLOYEE)
      HrLite::TaxDeclaration.create!(user_id: other.id, regime: "old",
                                     financial_year: HrLite::FinancialYear.start_for(Date.current))

      get "/hr/tax_declaration"
      expect(HrLite::TaxDeclaration.where(user_id: employee.id).count).to eq(0)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "HR checking the proof" do
    let!(:declaration) do
      d = HrLite::TaxDeclaration.create!(
        user_id: employee.id, regime: "old",
        financial_year: HrLite::FinancialYear.start_for(Date.current)
      )
      d.tax_declaration_items.create!(section: "80c", declared_amount: BigDecimal("150000"))
      d.submit!(actor: employee)
      d
    end

    it "records what the proof supported, which can be less than claimed" do
      sign_in finance
      item = declaration.tax_declaration_items.first

      patch "/hr/admin/tax_declarations/#{declaration.id}", params: {
        tax_declaration: { tax_declaration_items_attributes: {
          "0" => { id: item.id, verified_amount: "90000" }
        } }
      }

      expect(item.reload.verified_amount).to eq(90_000)
      # Not yet verified, so payroll still deducts against the claim — making
      # somebody overpay all year because paperwork is slow is its own wrong.
      expect(declaration.reload.allowable_total).to eq(150_000)

      post "/hr/admin/tax_declarations/#{declaration.id}/verify"
      expect(declaration.reload).to be_verified
      expect(declaration.allowable_total).to eq(90_000)
    end

    it "will not send one back without a reason" do
      sign_in finance
      post "/hr/admin/tax_declarations/#{declaration.id}/reject", params: { note: "" }

      expect(flash[:alert]).to include("what is missing")
      expect(declaration.reload).to be_submitted
    end

    it "keeps an employee out" do
      sign_in employee
      get "/hr/admin/tax_declarations"
      expect(response).to redirect_to("/hr/")
    end

    it "lists by status and opens one" do
      sign_in finance
      get "/hr/admin/tax_declarations"
      expect(response.body).to include("Meera")

      get "/hr/admin/tax_declarations?status=draft"
      expect(response.body).not_to include("Meera")

      get "/hr/admin/tax_declarations/#{declaration.id}"
      expect(response.body).to include("80C", "1,50,000")
    end

    it "sends one back with a reason" do
      sign_in finance
      post "/hr/admin/tax_declarations/#{declaration.id}/reject", params: { note: "No 80C proof" }

      expect(declaration.reload).to be_rejected
      expect(declaration.note).to eq("No 80C proof")
    end

    it "refuses to verify one that is not submitted" do
      declaration.reject!(actor: finance, note: "missing")
      sign_in finance

      post "/hr/admin/tax_declarations/#{declaration.id}/verify"
      expect(flash[:alert]).to include("submitted")
    end

    it "re-renders a bad verified amount rather than losing the page" do
      sign_in finance
      item = declaration.tax_declaration_items.first

      patch "/hr/admin/tax_declarations/#{declaration.id}", params: {
        tax_declaration: { tax_declaration_items_attributes: {
          "0" => { id: item.id, verified_amount: "-5" }
        } }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

RSpec.describe "Loans over HTTP", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN) }
  let(:hr) { user_with_roles(HrLite::Role::HR) }

  def loan_for(user, principal: 60_000, instalment: 5_000)
    HrLite::Loan.create!(user_id: user.id, principal: BigDecimal(principal.to_s),
                         monthly_instalment: BigDecimal(instalment.to_s),
                         starts_on: Date.current.beginning_of_month)
  end

  it "shows an employee what they owe and what comes out next" do
    loan_for(employee)
    sign_in employee

    get "/hr/loans"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("60,000")
  end

  it "shows nobody else's" do
    loan_for(owner, principal: 99_999)
    sign_in employee

    get "/hr/loans"
    expect(response.body).not_to include("99,999")
  end

  describe "the money tier" do
    before { sign_in owner }

    it "lists loans by status and opens one" do
      loan = loan_for(employee)
      get "/hr/admin/loans"
      expect(response.body).to include("Meera", "60,000")

      get "/hr/admin/loans?status=closed"
      expect(response.body).not_to include("Meera")

      get "/hr/admin/loans/new"
      expect(response).to have_http_status(:ok)

      get "/hr/admin/loans/#{loan.id}"
      expect(response.body).to include("5,000")
    end

    it "records a loan that payroll will deduct" do
      expect {
        post "/hr/admin/loans", params: {
          loan: { user_id: employee.id, principal: "60000", monthly_instalment: "5000",
                  starts_on: Date.current.beginning_of_month.to_s, reason: "Advance" }
        }
      }.to change(HrLite::Loan, :count).by(1)

      loan = HrLite::Loan.last
      expect(loan.outstanding).to eq(60_000)
      expect(loan.approved_by_id).to eq(owner.id)
    end

    it "refuses an instalment larger than the loan" do
      post "/hr/admin/loans", params: {
        loan: { user_id: employee.id, principal: "5000", monthly_instalment: "9000",
                starts_on: Date.current.to_s }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "closes a loan without erasing what was already deducted" do
      loan = loan_for(employee)
      loan.loan_repayments.create!(period_month: Date.current.beginning_of_month,
                                   amount: BigDecimal("5000"))

      post "/hr/admin/loans/#{loan.id}/close"

      expect(loan.reload).to be_closed
      expect(loan.repaid).to eq(5_000)
      expect(loan.outstanding).to eq(55_000)
    end

    # Cancelling says the loan never happened. Money that has already left
    # somebody's salary says otherwise.
    it "refuses to cancel once an instalment has been taken" do
      loan = loan_for(employee)
      loan.loan_repayments.create!(period_month: Date.current.beginning_of_month,
                                   amount: BigDecimal("5000"))

      post "/hr/admin/loans/#{loan.id}/cancel"

      expect(flash[:alert]).to include("Close it instead")
      expect(loan.reload).to be_active
    end

    it "cancels one that has not been deducted yet" do
      loan = loan_for(employee)
      post "/hr/admin/loans/#{loan.id}/cancel"
      expect(loan.reload).to be_cancelled
    end
  end

  it "keeps HR out of the loan screens — an instalment is pay" do
    sign_in hr
    get "/hr/admin/loans"
    expect(response).to redirect_to("/hr/")
  end
end
