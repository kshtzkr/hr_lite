require "rails_helper"

# The menu is nine places with tabs, drawn from one list. These guard the
# three ways it can go wrong: a tab that leads to a refusal, a screen that
# drops out of the menu, and one name meaning two things.
RSpec.describe "Menu places and tabs", type: :request do
  ROLES = HrLite::Role.then { |r| [ r::EMPLOYEE, r::MANAGER, r::HR, r::FINANCE, r::LEADERSHIP, r::SUPER_ADMIN, r::CA ] }

  before do
    HrLite.config.office_geofence = true
    HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Two-step", active: true)
  end

  def tab_hrefs
    get "/hr/"
    places = Nokogiri::HTML(response.body).css(".hrl-side__nav a").map { |a| a["href"] }
    places.flat_map do |href|
      get href
      [ href ] + Nokogiri::HTML(response.body).css(".hrl-tabrow a").map { |a| a["href"] }
    end.uniq
  end

  ROLES.each do |role|
    it "opens every place and tab a #{role} is shown" do
      sign_in role == HrLite::Role::CA ? user_with_roles(role) : user_with_roles(HrLite::Role::EMPLOYEE, role) # everyone on staff holds Employee
      hrefs = tab_hrefs
      expect(hrefs).not_to be_empty
      aggregate_failures do
        hrefs.each do |href|
          get href
          expect(response).to have_http_status(:ok), "#{role}: #{href} answered #{response.status}"
        end
      end
    end
  end

  it "shows a team-scope manager the team pages they can open" do
    sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER)
    expect(tab_hrefs).to include(*%w[
      /admin/overview /admin/attendances /admin/work_modes /admin/leave_balances /admin/leave_requests
      /admin/comp_off_requests /admin/regularization_requests /admin/wfh_requests /admin/work_locations /admin/reports
    ].map { |path| "/hr#{path}" })
  end

  it "counts only the manager's team in the Inbox badges" do
    create(:comp_off_request) # someone outside the manager's team
    sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER)
    get "/hr/admin/comp_off_requests"
    expect(Nokogiri::HTML(response.body).css(".hrl-tabrow .hrl-badge")).to be_empty
  end

  it "keeps every screen the old menu reached" do
    sign_in user_with_roles(*ROLES)
    old_menu = %w[
      / /attendance /leave_requests /team /calendar /expenses /benefits /salary_slips /tax_declaration /loans
      /profile /documents /id_card /career /timeline /admin/ca_reviews /policies /hr_requests /org /kudos /approvals
      /admin/overview /admin/attendances /admin/work_modes /admin/work_time /admin/leave_requests /admin/reports
      /admin/expenses /admin/hr_requests /admin/assets /admin/benefits /admin/payroll_runs /admin/tax_declarations
      /admin/checklists /admin/employees /admin/awards /admin/leave_types /admin/audit_logs /admin/policies
      /admin/documents /admin/roles /admin/statutory_rate_cards /admin/loans /admin/performance_plans
      /work_time /admin/leave_balances /admin/comp_off_requests /admin/regularization_requests
      /admin/wfh_requests /admin/work_locations
    ].map { |path| "/hr#{path}".chomp("/").then { |p| p == "/hr" ? "/hr/" : p } }
    expect(old_menu - tab_hrefs).to be_empty
  end

  it "gives every place and tab its own name" do
    labels = HrLite::ApplicationHelper::SECTIONS.flat_map { |s| [ s[:label] ] + s[:tabs].map { |t| t[:label] } }
    expect(labels.tally.select { |_, n| n > 1 }.keys).to be_empty
  end
end
