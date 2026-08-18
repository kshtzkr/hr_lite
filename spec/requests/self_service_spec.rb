require "rails_helper"

# The screens four PRs of engine have been waiting for. Every one of them is
# scoped to the signed-in person the same way the older self-service screens
# are: a foreign id 404s through the relation rather than 403ing.
RSpec.describe "Employee self-service", type: :request, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:colleague) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }

  before { sign_in employee }

  describe "expenses" do
    let!(:category) do
      HrLite::ExpenseCategory.create!(name: "Travel", monthly_cap: 5_000,
                                      receipt_required: false)
    end

    it "shows what is left of each cap this month" do
      get "/hr/expenses"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Travel", "left")
    end

    it "claims, and the claim is submitted rather than left in a drawer" do
      expect {
        post "/hr/expenses", params: { expense: {
          category_id: category.id, amount: "1200", spent_on: Date.current.to_s,
          description: "Cab to the airport"
        } }
      }.to change(HrLite::Expense, :count).by(1)

      expect(HrLite::Expense.last).to be_submitted
      expect(HrLite::Expense.last.user_id).to eq(employee.id)
    end

    # The cap is enforced at claim time, and the form has to say so.
    it "re-renders with the cap message rather than losing what was typed" do
      post "/hr/expenses", params: { expense: {
        category_id: category.id, amount: "9000", spent_on: Date.current.to_s,
        description: "Flight"
      } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("over the Travel cap")
    end

    it "withdraws a claim that is still waiting" do
      post "/hr/expenses", params: { expense: {
        category_id: category.id, amount: "500", spent_on: Date.current.to_s, description: "Bus"
      } }
      expense = HrLite::Expense.last

      post "/hr/expenses/#{expense.id}/cancel"
      expect(expense.reload).to be_cancelled
    end

    it "will not withdraw one that has been decided" do
      post "/hr/expenses", params: { expense: {
        category_id: category.id, amount: "500", spent_on: Date.current.to_s, description: "Bus"
      } }
      expense = HrLite::Expense.last
      expense.approve!(actor: finance)

      post "/hr/expenses/#{expense.id}/cancel"
      expect(flash[:alert]).to include("still waiting")
      expect(expense.reload).to be_approved
    end

    it "404s on somebody else's claim" do
      theirs = HrLite::Expense.create!(user_id: colleague.id, category: category, amount: 100,
                                       spent_on: Date.current, description: "Theirs")

      post "/hr/expenses/#{theirs.id}/cancel"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "benefits" do
    it "shows what this person is covered for, and nobody else" do
      benefit = HrLite::Benefit.create!(name: "Group health", kind: "health",
                                        provider: "Acme", coverage: 500_000)
      HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                        enrolled_on: Date.current - 30, dependants: 2)
      other = HrLite::Benefit.create!(name: "Directors cover", kind: "life")
      HrLite::BenefitEnrolment.create!(benefit: other, user_id: colleague.id,
                                        enrolled_on: Date.current - 30)

      get "/hr/benefits"

      expect(response.body).to include("Group health", "Acme")
      expect(response.body).not_to include("Directors cover")
    end

    it "says so plainly when there is nothing" do
      get "/hr/benefits"
      expect(response.body).to include("not enrolled in any benefit")
    end
  end

  describe "policies" do
    let!(:policy) do
      HrLite::Policy.create!(title: "Code of conduct", body: "Be decent.",
                             effective_from: Date.current, published: true,
                             acknowledgement_required: true)
    end

    it "flags what still needs acknowledging, then records it" do
      get "/hr/policies"
      expect(response.body).to include("Needs your acknowledgement")

      post "/hr/policies/#{policy.id}/acknowledge"
      expect(policy.reload).to be_acknowledged_by(employee)

      get "/hr/policies"
      expect(response.body).to include("Read")
    end

    it "shows only the version in force" do
      policy.supersede!(body: "Be decent and be on time.")

      get "/hr/policies"
      expect(response.body).to include("v2")
      expect(response.body).not_to include("v1")
    end

    it "will not open an unpublished policy" do
      draft = HrLite::Policy.create!(title: "Draft", body: "x",
                                     effective_from: Date.current, published: false)

      get "/hr/policies/#{draft.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "asking HR" do
    it "raises a request and lists it" do
      expect {
        post "/hr/hr_requests", params: { hr_request: {
          category: "salary_certificate", subject: "Certificate for a visa",
          body: "Embassy needs it by Friday."
        } }
      }.to change(HrLite::HrRequest, :count).by(1)

      get "/hr/hr_requests"
      expect(response.body).to include("Certificate for a visa", "Salary certificate")
    end

    it "shows HR's answer once there is one" do
      request = HrLite::HrRequest.create!(user_id: employee.id, category: "payroll_query",
                                          subject: "PF query")
      request.resolve!(actor: finance, resolution: "Sorted — see your March slip.")

      get "/hr/hr_requests/#{request.id}"
      expect(response.body).to include("HR's answer", "see your March slip")
    end

    it "404s on somebody else's request" do
      theirs = HrLite::HrRequest.create!(user_id: colleague.id, category: "other",
                                         subject: "Theirs")

      get "/hr/hr_requests/#{theirs.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "re-renders an incomplete request" do
      post "/hr/hr_requests", params: { hr_request: { category: "other", subject: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

RSpec.describe "Self-service screens that had no test", type: :request, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  before { sign_in employee }

  it "opens the new-claim form with today already filled in" do
    HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    get "/hr/expenses/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Date.current.to_s, "Travel")
  end

  it "opens the ask-HR form" do
    get "/hr/hr_requests/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Salary certificate")
  end

  it "withdraws an open request" do
    request = HrLite::HrRequest.create!(user_id: employee.id, category: "other",
                                        subject: "Never mind")
    post "/hr/hr_requests/#{request.id}/cancel"

    expect(request.reload).to be_cancelled
    expect(flash[:notice]).to include("withdrawn")
  end

  it "says so rather than 500ing when the request was already answered" do
    request = HrLite::HrRequest.create!(user_id: employee.id, category: "other",
                                        subject: "Answered already")
    request.resolve!(actor: hr, resolution: "Done")

    post "/hr/hr_requests/#{request.id}/cancel"

    expect(flash[:alert]).to include("already been answered")
    expect(request.reload).to be_resolved
  end
end

RSpec.describe "The reports hub itself", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "lists only the reports this person could actually open" do
    sign_in hr
    get "/hr/admin/reports"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Headcount by department")
    expect(response.body).not_to include("Expense claims") # HR cannot approve expenses
  end

  it "turns away somebody who can see no report at all" do
    sign_in employee
    get "/hr/admin/reports"

    expect(response).to redirect_to("/hr/")
  end

  it "takes the month from the query string" do
    sign_in hr
    get "/hr/admin/reports", params: { month: "2027-03" }

    expect(response.body).to include("2027-03")
  end
end
