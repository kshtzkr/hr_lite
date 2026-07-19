require "rails_helper"

# Pins the privacy contract: salary and identity data are visible ONLY to
# the person themselves (masked) and the governing tier — never to other
# employees, and never on any everyone-visible surface.
RSpec.describe "Privacy boundaries", type: :request do
  let(:me) { create(:user, name: "Meera") }
  let(:colleague) { create(:user, name: "Dev Colleague") }
  let!(:colleague_profile) do
    create(:employee_profile, user: colleague, pan_number: "ZYXWV9876K",
                              bank_account_number: "111222333444", pf_uan: "999888777666")
  end
  let!(:colleague_structure) { create(:salary_structure, user: colleague, basic: BigDecimal("777777")) }

  before { sign_in me }

  it "blocks another employee's salary slips" do
    run = create(:payroll_run, status: "draft")
    slip = create(:salary_slip, payroll_run: run, user: colleague)
    run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    get "/hr/salary_slips/#{slip.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "keeps admin employee pages (profiles, structures) away from plain employees" do
    get "/hr/admin/employees/#{colleague_profile.id}"
    expect(response).to have_http_status(:redirect) # bounced by the admin gate

    get "/hr/admin/employees/#{colleague_profile.id}/salary_structures/new"
    expect(response).to have_http_status(:redirect)
  end

  it "shows a colleague's name but never their numbers on shared surfaces" do
    [ "/hr/team", "/hr/org", "/hr/calendar" ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "#{path} should render"
      expect(response.body).not_to include("777777"), "#{path} leaked salary"
      expect(response.body).not_to include("ZYXWV9876K"), "#{path} leaked PAN"
      expect(response.body).not_to include("111222333444"), "#{path} leaked bank account"
    end
  end

  it "masks even the owner's own identity numbers on their profile" do
    profile = create(:employee_profile, user: me, pan_number: "ABCDE1234F",
                                        bank_account_number: "555666777888")
    get "/hr/profile"
    expect(response.body).not_to include("ABCDE1234F")
    expect(response.body).to include(profile.masked_pan)
    expect(response.body).to include("•••• 7888")
  end

  it "keeps the admin tier out of payroll (leadership-only money)" do
    admin = create(:user, admin: true)
    sign_in admin
    get "/hr/admin/payroll_runs"
    expect(response).to have_http_status(:redirect)

    get "/hr/admin/employees/#{colleague_profile.id}"
    expect(response).to have_http_status(:redirect) # employees screen is leadership-tier
  end
end
