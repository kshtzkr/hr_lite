require "rails_helper"

# Guards that stand between an admin's typo and someone's salary. Each one
# shipped without a test; each one is the only thing between a stray keystroke
# and a wrong payslip.
RSpec.describe "Slip override guards", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:month) { Date.new(2027, 6, 1) }

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  before do
    HrLite.config.leadership_emails = [ leader.email ]
    sign_in leader
  end

  let(:slip) do
    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)
    run = create(:payroll_run, period_month: month)
    run.compute!(actor: leader)
    run.salary_slips.first
  end

  def override(**params)
    patch "/hr/admin/salary_slips/#{slip.id}", params: { salary_slip: params }
  end

  it "refuses an LOP above the days in the month" do
    override(lop_override: slip.days_in_month + 1)

    expect(response).to redirect_to("/hr/admin/salary_slips/#{slip.id}")
    expect(flash[:alert]).to include("between 0 and #{slip.days_in_month}")
    expect(slip.reload.lop_override).to be_nil
  end

  it "refuses a negative LOP — it would pay for days nobody worked" do
    override(lop_override: -1)
    expect(flash[:alert]).to include("between 0 and")
    expect(slip.reload.lop_override).to be_nil
  end

  it "refuses negative TDS" do
    override(tds_override: -500)
    expect(flash[:alert]).to eq("TDS cannot be negative.")
    expect(slip.reload.tds_override).to be_nil
  end

  it "refuses to recompute a slip whose structure has since been removed" do
    target = slip
    HrLite::SalaryStructure.where(user_id: target.user_id).delete_all

    patch "/hr/admin/salary_slips/#{target.id}", params: { salary_slip: { lop_override: 1 } }
    expect(flash[:alert]).to include("No salary structure is effective for June 2027")
  end
end

RSpec.describe "Offboarding failure paths", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }

  before do
    HrLite.config.leadership_emails = [ leader.email ]
    sign_in leader
  end

  it "reports the validation error rather than 500ing" do
    profile = create(:employee_profile, date_of_joining: Date.current)

    # An exit before the joining date is the mistake this rescue exists for.
    post "/hr/admin/employees/#{profile.id}/offboard",
         params: { date_of_exit: (Date.current - 30).to_s }

    expect(response).to redirect_to("/hr/admin/employees/#{profile.id}")
    expect(flash[:alert]).to be_present
    expect(profile.reload.date_of_exit).to be_nil
  end
end

RSpec.describe "Resignation screen", type: :request do
  let(:employee) { create(:employee_profile).user }

  before { sign_in employee }

  it "offers a fresh form once a previous resignation was withdrawn" do
    resignation = HrLite::Resignation.create!(user: employee,
                                              proposed_last_day: Date.current + 30)
    resignation.withdraw!(actor: employee)

    get "/hr/resignation"
    expect(response.body).to include("form")
  end
end
