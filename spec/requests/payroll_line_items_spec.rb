require "rails_helper"

# PayrollLineItem reached payslips since 0.14 but had no screen — a bonus was
# a console session.
RSpec.describe "One-off payroll items over HTTP", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN) }
  let(:hr) { user_with_roles(HrLite::Role::HR) }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:month) { Date.new(2027, 6, 1) }

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  before do
    HrLite::SalaryComponent.seed_defaults!
    create(:employee_profile, user: employee)
    create(:salary_structure, user: employee)
  end

  def add(code, amount)
    post "/hr/admin/payroll_line_items", params: { payroll_line_item: {
      user_id: employee.id, component_id: HrLite::SalaryComponent.find_by!(code: code).id,
      period_month: "2027-06", amount: amount, note: "Q1 target"
    } }
  end

  describe "the money tier" do
    before { sign_in owner }

    it "adds an incentive that the month's computed slip then carries" do
      run = create(:payroll_run, period_month: month)
      get "/hr/admin/payroll_runs/#{run.id}"
      expect(response.body).to include("/hr/admin/payroll_line_items?month=2027-06")
      get "/hr/admin/payroll_line_items/new?month=2027-06"
      expect(response.body).to include("Incentive (earning)").and include("2027-06")
      expect(response.body).not_to include("Loan repayment")

      expect { add("incentive", "7500") }.to change(HrLite::PayrollLineItem, :count).by(1)
      expect(response).to redirect_to("/hr/admin/payroll_line_items?month=2027-06")
      expect(HrLite::PayrollLineItem.last).to have_attributes(period_month: month, amount: 7500,
                                                              created_by_id: owner.id)

      get "/hr/admin/payroll_line_items?month=2027-06"
      expect(response.body).to include("Meera", "Incentive", "7,500", "Q1 target")
      get "/hr/admin/payroll_line_items?month=2027-05"
      expect(response.body).not_to include("Q1 target")

      post "/hr/admin/payroll_runs/#{run.id}/compute"
      incentive = run.salary_slips.find_by!(user_id: employee.id)
                     .earnings_rows.find { |row| row["code"] == "incentive" }
      expect(BigDecimal(incentive["amount"])).to eq(7500)
    end

    it "refuses an amount that is not above zero" do
      expect { add("bonus", "0") }.not_to change(HrLite::PayrollLineItem, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("must be more than zero")
    end

    it "refuses a month that has already been paid, with the model's reason" do
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: owner)
      run.finalize!(actor: owner)

      expect { add("bonus", "5000") }.not_to change(HrLite::PayrollLineItem, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has already been paid")
    end

    it "removes an item" do
      add("bonus", "5000")
      item = HrLite::PayrollLineItem.last

      delete "/hr/admin/payroll_line_items/#{item.id}"

      expect(HrLite::PayrollLineItem.exists?(item.id)).to be(false)
      expect(response).to redirect_to("/hr/admin/payroll_line_items?month=2027-06")
    end
  end

  it "keeps HR out — a bonus is pay" do
    sign_in hr
    expect { add("bonus", "5000") }.not_to change(HrLite::PayrollLineItem, :count)
    expect(response).to redirect_to("/hr/")
    get "/hr/admin/payroll_line_items"
    expect(response).to redirect_to("/hr/")
  end
end
