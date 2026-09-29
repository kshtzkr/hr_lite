require "rails_helper"

RSpec.describe "Navigation that leads somewhere", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

    it "hides the employee Approvals inbox until an approval flow exists" do
      sign_in employee
      get "/hr/"
      expect(response.body).not_to include('href="/hr/approvals"')

      HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Two-step", active: true)
      get "/hr/"
      expect(response.body).to include('href="/hr/approvals"')
    end

    it "links My profile and the balance pages" do
      sign_in employee
      get "/hr/leave_requests"
      expect(response.body).to include('href="/hr/profile"').and include('href="/hr/leave_balances"')
      sign_in hr
      get "/hr/admin/leave_requests"
      expect(response.body).to include('href="/hr/admin/leave_balances"')
    end

    it "shows Claims to whoever approves claims, and only them" do
      sign_in hr
      get "/hr/"
      expect(response.body).not_to include('href="/hr/admin/expenses"')

      finance = user_with_roles(HrLite::Role::FINANCE, name: "Farah")
      sign_in finance
      get "/hr/"
      expect(response.body).to include('href="/hr/admin/expenses"')
      expect(response.body).not_to include('href="/hr/admin/overview"')
    end
end
