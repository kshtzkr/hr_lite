require "rails_helper"

# The money tier: with superadmin_emails configured, ordinary leadership
# governs people and policy but never sees another person's pay; only
# superadmins reach salary structures, payroll, slips, appraisals and
# promotions.
RSpec.describe "Superadmin tier", type: :request do
  let(:leader) { create(:user, email: "lead@x.test", name: "Plain Leader") }
  let(:owner) { create(:user, email: "owner@x.test", name: "Owner") }
  let(:profile) { create(:employee_profile) }

  before do
    HrLite.config.leadership_emails = [ "lead@x.test", "owner@x.test" ]
    HrLite.config.superadmin_emails = [ "owner@x.test" ]
  end

  describe "plain leadership (not superadmin)" do
    before { sign_in leader }

    it "still governs people: employees list and onboarding stay open" do
      get "/hr/admin/employees"
      expect(response).to have_http_status(:ok)
      get "/hr/admin/employees/new"
      expect(response).to have_http_status(:ok)
    end

    it "is bounced from every money screen" do
      [ "/hr/admin/payroll_runs",
        "/hr/admin/employees/#{profile.id}/salary_structures/new",
        "/hr/admin/employees/#{profile.id}/appraisals/new",
        "/hr/admin/employees/#{profile.id}/designation_changes/new" ].each do |path|
        get path
        expect(response).to have_http_status(:redirect), "#{path} should be superadmin-only"
      end
    end

    it "sees the employee page without salary or appraisal data" do
      create(:salary_structure, user: profile.user, basic: BigDecimal("424242"))
      get "/hr/admin/employees/#{profile.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Salary structures")
      expect(response.body).not_to include("424")
      expect(response.body).not_to include("New structure")
      expect(response.body).not_to include("New appraisal")
    end

    it "has no Payroll item in the rail" do
      get "/hr/admin/employees"
      expect(response.body).not_to include("/admin/payroll_runs")
    end
  end

  describe "superadmin" do
    before { sign_in owner }

    it "reaches the money screens and sees structures on the employee page" do
      get "/hr/admin/payroll_runs"
      expect(response).to have_http_status(:ok)

      create(:salary_structure, user: profile.user)
      get "/hr/admin/employees/#{profile.id}"
      expect(response.body).to include("Salary structures").and include("New structure")
      expect(response.body).to include("/admin/payroll_runs")
    end
  end

  it "keeps pre-0.5.0 behaviour when superadmin_emails is left empty" do
    HrLite.config.superadmin_emails = []
    sign_in leader
    get "/hr/admin/payroll_runs"
    expect(response).to have_http_status(:ok)
  end

  it "keeps employees' own published slips readable (only OTHERS' pay is hidden)" do
    run = create(:payroll_run, status: "draft")
    slip = create(:salary_slip, payroll_run: run, user: leader)
    run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    sign_in leader
    get "/hr/salary_slips/#{slip.id}"
    expect(response).to have_http_status(:ok)
  end
end
