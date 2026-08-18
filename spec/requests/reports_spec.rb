require "rails_helper"

# A report must not be a side door into rows somebody cannot otherwise reach.
# Each one is scoped by the SAME permission that guards the screen its data
# comes from.
RSpec.describe "Reports", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let!(:report_to) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:stranger) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }
  let(:month) { Date.current.beginning_of_month }

  before do
    create(:employee_profile, user: report_to, manager_id: manager.id, department: "Operations")
    create(:employee_profile, user: stranger, department: "Sales")
    create(:employee_profile, user: manager, department: "Operations")
  end

  describe "headcount" do
    it "gives HR the whole company" do
      sign_in hr
      get "/hr/admin/reports/headcount"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Operations", "Sales")
    end

    # The manager's report shows their own team, not the company.
    it "gives a manager only their own people" do
      sign_in manager
      get "/hr/admin/reports/headcount"

      expect(response.body).to include("Operations")
      expect(response.body).not_to include("Sales")
    end
  end

  describe "the expense report" do
    it "is refused to somebody who cannot approve expenses" do
      sign_in manager
      get "/hr/admin/reports/expenses"

      expect(response).to redirect_to("/hr/")
    end

    it "opens for finance" do
      category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
      HrLite::Expense.create!(user_id: report_to.id, category: category, amount: 900,
                              spent_on: month, description: "Cab")
      sign_in finance
      get "/hr/admin/reports/expenses"

      expect(response.body).to include("Travel", "Meera")
    end
  end

  describe "CSV" do
    it "downloads, and the download is audited" do
      sign_in hr

      expect {
        get "/hr/admin/reports/headcount.csv"
      }.to change { HrLite::AuditLog.where(action: "report.exported").count }.by(1)

      expect(response.header["Content-Type"]).to include("text/csv")
      expect(response.body).to include("Department,People")
    end

    it "names the file for the report and the month" do
      sign_in hr
      get "/hr/admin/reports/headcount.csv", params: { month: "2027-06" }

      expect(response.header["Content-Disposition"]).to include("headcount-2027-06.csv")
    end
  end

  describe "an unknown report" do
    it "is refused rather than 500ing" do
      sign_in hr
      get "/hr/admin/reports/everything"

      expect(response).to redirect_to("/hr/")
    end
  end

  describe "the other reports" do
    before { sign_in hr }

    it "renders joiners and leavers" do
      HrLite::EmployeeProfile.find_by!(user_id: report_to.id)
                             .update!(date_of_joining: month + 2)
      get "/hr/admin/reports/joiners_and_leavers"

      expect(response.body).to include("Meera")
    end

    it "renders leave balances" do
      create(:leave_type, code: "CL", annual_quota: 12)
      get "/hr/admin/reports/leave_balances"

      expect(response.body).to include("CL")
    end

    it "renders the attendance summary" do
      get "/hr/admin/reports/attendance"
      expect(response.body).to include("Payable days")
    end

    it "says so plainly when a month has nothing in it" do
      get "/hr/admin/reports/joiners_and_leavers", params: { month: "2019-01" }
      expect(response.body).to include("Nothing to report")
    end
  end
end
