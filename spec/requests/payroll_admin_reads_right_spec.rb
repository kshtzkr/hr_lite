require "rails_helper"

# HRMS audit lane F2: the payroll run, help desk, reports, rate cards and menu say what is true.
RSpec.describe "Payroll and admin pages read right", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  it "makes Compute the next step on a draft and shows days without .0 (PY-8, PY-10)" do
    run = create(:payroll_run, period_month: Date.new(2027, 6, 1))
    sign_in owner
    get "/hr/admin/payroll_runs/#{run.id}"
    expect(response.body).to match(/<button class="hrl-btn hrl-btn--primary" type="submit">Compute</)
    create(:salary_structure, user: create(:employee_profile).user)
    run.compute!(actor: owner)
    get "/hr/admin/payroll_runs/#{run.id}"
    expect(response.body).to include("<th>Paid days</th>").and match(%r{data-label="Paid days" class="hrl-num">\d+(\.5)?</td>})
  end

  it "names whom the help-desk answer goes to (VS-19)" do
    asker = create(:user, name: "Meera")
    ticket = HrLite::HrRequest.create!(user_id: asker.id, category: "salary_certificate", subject: "Salary certificate", body: "For the bank")
    sign_in owner
    get "/hr/admin/hr_requests/#{ticket.id}"
    expect(response.body).to include("Answer to Meera")
  end

  it "picks the report month from a month field (AD-5)" do
    sign_in owner
    get "/hr/admin/reports"
    expect(response.body).to include('type="month" name="month"')
  end

  it "says which rate card payroll uses today (VS-26)" do
    HrLite::StatutorySeeds.call
    sign_in owner
    get "/hr/admin/statutory_rate_cards"
    expect(response.body.scan(">In force</span>").size).to eq(1)
  end

  it "colours paid claims as done and drafts as quiet (EX-5)" do
    helper = Object.new.extend(ActionView::Helpers::TagHelper, HrLite::ApplicationHelper)
    expect(helper.hrl_request_status_badge("reimbursed")).to include("hrl-badge--ok")
    expect(helper.hrl_request_status_badge("draft")).to include("hrl-badge--muted")
  end
end
