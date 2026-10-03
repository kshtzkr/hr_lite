require "rails_helper"

# Findings from the 2026-10 security audit. Each example is the refusal or
# the redaction; the happy paths live in each screen's own spec.
RSpec.describe "Security audit 2026-10", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }

  def pdf = { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "scan.pdf", content_type: "application/pdf" }

  describe "government ID numbers" do
    it "stores a document number encrypted, so it never reaches the audit diff in plain text" do
      doc = HrLite::Document.create!(user_id: hr.id, category: "aadhaar", title: "Aadhaar",
                                     reference_number: "1234 5678 9012", file: pdf)

      raw = HrLite::Document.connection.select_value("SELECT reference_number FROM hr_lite_documents WHERE id = #{doc.id}")
      expect(raw).not_to include("1234 5678 9012")
      expect(HrLite::AuditLog.where(subject: doc).pluck(:audited_changes).to_s).not_to include("1234 5678 9012")
    end

    it "treats loans as money-tier in audit mail" do
      expect(HrLite::AuditLog::MONEY_TIER_TYPES).to include("HrLite::Loan")
    end
  end

  describe "nobody edits their own records from the admin screens" do
    it "refuses HR rewriting its own attendance" do
      date = Date.current - 2
      sign_in hr

      patch "/hr/admin/attendances/#{hr.id}", params: {
        date: date.to_s,
        attendance_record: { check_in_at: "#{date}T09:00", check_out_at: "#{date}T18:00", status: "present",
                             regularization_note: "self" }
      }

      expect(HrLite::AttendanceRecord.where(user_id: hr.id, date: date)).to be_empty
    end

    it "refuses HR adjusting its own leave balance" do
      type = create(:leave_type, code: "CL", name: "Casual", annual_quota: 12)
      sign_in hr

      expect {
        post "/hr/admin/leave_balances/adjust", params: { user_id: hr.id, leave_type_id: type.id, delta: "20",
                                                          year: Date.current.year, note: "self" }
      }.not_to change(HrLite::LeaveBalance, :count)
    end

    it "refuses Finance verifying its own tax declaration" do
      declaration = HrLite::TaxDeclaration.create!(user_id: finance.id, regime: "old",
                                                   financial_year: HrLite::FinancialYear.start_for(Date.current))
      declaration.tax_declaration_items.create!(section: "80c", declared_amount: BigDecimal("150000"))
      declaration.submit!(actor: finance)
      sign_in finance

      post "/hr/admin/tax_declarations/#{declaration.id}/verify"

      expect(declaration.reload).not_to be_verified
    end
  end

  it "does not let a rejected tax declaration lower TDS" do
    employee = create(:employee_profile, declared_annual_deductions: 0).user
    declaration = HrLite::TaxDeclaration.create!(user_id: employee.id, regime: "old",
                                                 financial_year: HrLite::FinancialYear.start_for(Date.current))
    declaration.tax_declaration_items.create!(section: "80c", declared_amount: BigDecimal("150000"))
    declaration.update_columns(status: "rejected")
    run = create(:payroll_run, period_month: Date.current.months_ago(2).beginning_of_month)

    builder = HrLite::SlipBuilder.allocate
    builder.instance_variable_set(:@user, employee)
    builder.instance_variable_set(:@run, run)
    builder.instance_variable_set(:@profile, employee_profile_for(employee))

    expect(builder.send(:annual_deductions)).to eq(0)
  end

  it "defuses a staff name that a spreadsheet would run as a formula" do
    create(:employee_profile, user: create(:user, name: %(=HYPERLINK("http://x","y"))), date_of_joining: Date.current)
    sign_in hr

    get "/hr/admin/reports/joiners_and_leavers.csv"

    expect(response.body).to include("HYPERLINK")

    expect(response.body).not_to match(/^"?=HYPERLINK/)
  end

  it "keeps the payout register behind its own export permission" do
    clerk = create(:user)
    role = HrLite::Role.create!(name: "Payroll clerk")
    role.role_grants.create!(permission_key: "payroll.manage", scope: "all")
    grant_role(clerk, "Payroll clerk")
    run = create(:payroll_run, period_month: Date.current.months_ago(2).beginning_of_month)
    sign_in clerk

    get "/hr/admin/payroll_runs/#{run.id}/register.csv"

    expect(response).to have_http_status(:forbidden)
  end

  it "shows a manager only their own reports on the overview" do
    type = create(:leave_type, code: "CL", name: "Casual", annual_quota: 12)
    day = (Date.current + 7).next_occurring(:wednesday)
    report = create(:employee_profile, manager_id: manager.id).user
    stranger = create(:user, name: "Stranger Sam")
    create(:leave_request, user: report, leave_type: type, start_date: day, end_date: day)
    create(:leave_request, user: stranger, leave_type: type, start_date: day, end_date: day)
    sign_in manager

    get "/hr/admin/overview"

    expect(response.body).not_to include("Stranger Sam")
  end

  it "refuses an expense receipt that is not a PDF or an image" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    expense = HrLite::Expense.new(user_id: hr.id, category: category, amount: 100, spent_on: Date.current, description: "Cab")
    expense.receipt.attach(io: StringIO.new("<script>x</script>"), filename: "r.html", content_type: "text/html")

    expect(expense).not_to be_valid
  end

  def employee_profile_for(user) = HrLite::EmployeeProfile.find_by(user_id: user.id)
end
