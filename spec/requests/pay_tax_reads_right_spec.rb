require "rails_helper"

# HRMS audit lane C: pay, tax and loan screens say what they mean.
RSpec.describe "Pay and tax screens read right", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Farid") }
  let(:leader) { create(:user, email: "lead@x.test") }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  def declaration(status, user: employee)
    HrLite::TaxDeclaration.create!(user_id: user.id, regime: "old",
                                   financial_year: HrLite::FinancialYear.start_for(Date.current)).tap do |d|
      d.tax_declaration_items.create!(section: "80c", declared_amount: BigDecimal("150000"))
      d.submit!(actor: user) unless status == "draft"
      d.update_columns(status: status) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it "labels the admin tax working and shows money as money (PY-9)" do
    slip = create(:salary_slip, user: employee, tax_details: { "regime" => "new", "taxable" => "656613.0",
                                                               "fy_tds_already_deducted" => "0.0", "months_remaining" => "6",
                                                               "high_income_review" => "false" }.to_json)
    sign_in leader
    get "/hr/admin/salary_slips/#{slip.id}"
    expect(response.body).to include("TDS already deducted this year", "₹6,56,613.00")
    expect(response.body).not_to include("High income review", "Fy tds")
  end

  it "offers the decision only on a submitted declaration (TX-5)" do
    sign_in finance
    get "/hr/admin/tax_declarations/#{declaration('submitted').id}"
    expect(response.body).to include("Accept all and verify")
    get "/hr/admin/tax_declarations/#{declaration('verified', user: create(:user)).id}"
    expect(response.body).not_to include("Accept all and verify")
  end

  it "closes every card it opens and names the state the HR side uses (TX-6, TX-7)" do
    declaration("verified")
    sign_in employee
    get "/hr/tax_declaration"
    body = response.body
    expect(body.scan("<section").size).to eq(body.scan("</section>").size)
    expect(body.scan("<details").size).to eq(body.scan("</details>").size)
    expect(body).to include(">Verified</span>").and include("Help › Ask HR")
  end

  it "shows a submitted declaration read-only, saying it is with HR (FB-21)" do
    declaration("submitted")
    sign_in employee
    get "/hr/tax_declaration"
    expect(response.body).to include("Sent to HR to check the proof.").and include("<fieldset class=\"hrl-field\" disabled>")
  end

  it "picks the reimbursement month from a month field (EX-7)" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    claim = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 900,
                                    spent_on: Date.current, description: "Bus")
    claim.update_columns(status: "approved") # rubocop:disable Rails/SkipsModelValidations
    sign_in finance
    get "/hr/admin/expenses", params: { status: "approved" }
    expect(response.body).to include('type="month" name="period_month"', "Paid with the payroll of")
  end

  it "lists the loan's facts with their labels at any width (EX-9)" do
    loan = HrLite::Loan.create!(user_id: employee.id, principal: BigDecimal("60000"),
                                monthly_instalment: BigDecimal("5000"), starts_on: Date.current.beginning_of_month)
    sign_in finance
    get "/hr/admin/loans/#{loan.id}"
    expect(response.body).to include('<dl class="hrl-deflist">', "<dt>Outstanding</dt>")
  end

  it "reads the typed CTC back as money (VS-14)" do
    profile = create(:employee_profile, user: employee)
    structure = create(:salary_structure, user: employee, annual_ctc: 1_281_600)
    sign_in leader
    get "/hr/admin/employees/#{profile.id}/salary_structures/#{structure.id}/edit"
    expect(response.body).to include("= ₹12,81,600.00 a year")
  end
end
