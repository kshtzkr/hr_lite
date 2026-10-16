require "rails_helper"

RSpec.describe "Global search", type: :request do
  let(:manager) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER) }
  let(:report) { create(:user, name: "Meera Rao") }
  let(:stranger) { create(:user, name: "Meera Shah") }

  before do
    create(:employee_profile, user: report, manager_id: manager.id, employee_code: "EMP042")
    create(:employee_profile, user: stranger)
  end

  def results(q, frame: true)
    get "/hr/search", params: { q: q, frame: (1 if frame) }.compact
    CGI.unescapeHTML(response.body)
  end

  it "finds an employee's own screens but no admin screens and no people" do
    sign_in report
    expect(results("penalty")).to include("Attendance · My attendance")
    expect(results("wfh")).to include("Attendance · My attendance") # its /wfh_requests path matches
    expect(results("settings")).to include("Nothing you can open matches")
    expect(results("meera")).not_to include("Meera Shah")
  end

  it "finds a manager's own team member, by name or code, and nobody outside the team" do
    sign_in manager
    body = results("meera")
    expect(body).to include("Meera Rao", "/hr/admin/attendances/#{report.id}/summary")
    expect(body).not_to include("Meera Shah")
    expect(results("emp042")).to include("Meera Rao")
  end

  it "lets HR find anyone and the Settings screen, and needs two letters" do
    sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR)
    expect(results("meera")).to include("Meera Rao", "Meera Shah")
    expect(results("m")).to include("Type at least 2 letters")
    expect(results("work from home", frame: false)).to include("Inbox · WFH", "<h1 class=\"hrl-page__title\">Search</h1>")
  end
end
