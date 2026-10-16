require "rails_helper"

# Actions that notify people, grant access or stamp an exit ask first.
RSpec.describe "Confirm before irreversible actions", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::SUPER_ADMIN, HrLite::Role::LEADERSHIP, name: "Asha") }
  let(:hr) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  def confirms = Nokogiri::HTML(response.body).css("[data-turbo-confirm]").map { |el| el["data-turbo-confirm"] }

  it "asks before an employee resigns" do
    sign_in meera
    get "/hr/resignation"
    expect(confirms).to include("Submit your resignation? Leadership is told straight away.")
  end

  it "asks before leadership accepts a resignation" do
    profile = create(:employee_profile, user: meera)
    HrLite::Resignation.create!(user: meera, proposed_last_day: Date.current + 30)
    sign_in owner
    get "/hr/admin/employees/#{profile.id}"
    expect(confirms).to include("Accept Meera's resignation? Payroll and attendance end on the last day you set.")
  end

  it "asks before a role is given, with nobody picked by default, and before its permissions change" do
    role = HrLite::Role.find_by!(name: HrLite::Role::HR)
    sign_in owner
    get "/hr/admin/roles/#{role.id}/edit"
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("select#user_id option")["value"]).to eq("")
    expect(page.at_css("select#user_id")["data-hrl-filter"]).to be_present
    expect(confirms).to include("Give the HR role to the person you picked? Their access changes at once.",
                                "Save? Everyone holding HR gets these permissions at once.")
  end

  it "says how many people a policy will notify, and links each published title" do
    meera
    policy = HrLite::Policy.create!(title: "Leave policy", body: "Text", effective_from: Date.current, published: true)
    sign_in owner
    get "/hr/admin/policies/new"
    expect(confirms).to include("Publish and notify #{HrLite.active_employees.size} people by email?")
    get "/hr/admin/policies"
    expect(response.body).to include(%(href="/hr/policies/#{policy.id}">Leave policy</a>))
  end

  it "asks before a PIP is saved, since failing it is final" do
    plan = HrLite::PerformancePlan.create!(user_id: meera.id, start_date: Date.current, end_date: Date.current + 30,
                                          goals: "Close 10 files", created_by_id: owner.id)
    sign_in owner
    get "/hr/admin/performance_plans/#{plan.id}/edit"
    expect(confirms).to include("Save? Passed or failed closes the plan for good and tells the employee.")
  end

  it "names the approval a recompute clears and the blocking warnings an approval skips" do
    run = create(:payroll_run, status: "review", first_approved_by_id: hr.id, first_approved_at: Time.current,
                               warnings: [ "No salary structure for Meera" ])
    sign_in owner
    get "/hr/admin/payroll_runs/#{run.id}"
    expect(confirms).to include("Recompute #{run.label}? This clears Chitra's approval.",
                                "Approve #{run.label}? This finalizes the run and publishes the slips.\n\nBlocking warnings: No salary structure for Meera")
  end

  it "asks before a leave, comp-off or fix decision, under one text link back to the list" do
    leave = create(:leave_request, user: meera)
    comp_off = create(:comp_off_request, user: meera)
    fix = create(:regularization_request, user: meera)
    sign_in hr
    get "/hr/admin/leave_requests/#{leave.id}"
    expect(confirms).to eq([ "Approve Meera's leave, #{leave.date_range_label}?", "Reject Meera's leave, #{leave.date_range_label}?" ])
    get "/hr/admin/comp_off_requests/#{comp_off.id}"
    expect(confirms).to eq([ "Credit 1 day of comp-off to Meera?", "Reject Meera's comp-off for #{comp_off.date_worked.strftime('%d %b %Y')}?" ])
    expect(Nokogiri::HTML(response.body).at_css("a.hrl-backlink")["href"]).to eq("/hr/admin/comp_off_requests")
    get "/hr/admin/regularization_requests/#{fix.id}"
    expect(confirms).to eq([ "Write the proposed times onto Meera's attendance for #{fix.date.strftime('%d %b %Y')}?" ])
    expect(Nokogiri::HTML(response.body).at_css("a.hrl-backlink")["href"]).to eq("/hr/admin/regularization_requests")
  end

  it "asks before ending cover and shows the end date afterwards" do
    benefit = HrLite::Benefit.create!(name: "Group health", kind: "health", coverage: 500_000)
    enrolment = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: meera.id, enrolled_on: Date.current - 30)
    sign_in hr
    get "/hr/admin/benefits"
    expect(confirms).to include("End Group health for Meera on the date picked?")
    expect(Nokogiri::HTML(response.body).at_css("label[for='ended-on-#{enrolment.id}']").text).to eq("Last day of cover")

    enrolment.update!(ended_on: Date.current)
    get "/hr/admin/benefits"
    expect(response.body).to include("Cover ends #{Date.current.strftime('%d %b %Y')}", %(value="Change end"))
  end
end
