require "rails_helper"

RSpec.describe "Payroll over HTTP", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:admin) { create(:user, :admin) }
  let(:month) { Date.new(2027, 6, 1) }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  describe "leadership gating" do
    it "blocks admins from payroll and employee profiles" do
      sign_in admin
      get "/hr/admin/payroll_runs"
      expect(response).to redirect_to("/hr/")
      get "/hr/admin/employees"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "employee profile + structure administration" do
    before { sign_in leader }

    it "creates a profile with encrypted PII and a structure" do
      staff = create(:user, name: "Asha")
      expect {
        post "/hr/admin/employees", params: { employee_profile: {
          user_id: staff.id, employee_code: "EMP001", designation: "Ops lead",
          date_of_joining: "2026-01-01", pan_number: "ABCDE1234F", pf_uan: "123456789012",
          bank_name: "HDFC", bank_account_number: "1234567890", bank_ifsc: "HDFC0001234",
          tax_regime: "new"
        } }
      }.to change(HrLite::EmployeeProfile, :count).by(1)

      profile = HrLite::EmployeeProfile.last
      post "/hr/admin/employees/#{profile.id}/salary_structures", params: { salary_structure: {
        effective_from: "2027-01-01", basic: "40000", hra: "20000", special_allowance: "15000",
        pf_applicable: "1", esi_applicable: "1", pt_state: "none"
      } }
      expect(HrLite::SalaryStructure.count).to eq(1)
      follow_redirect!
      expect(response.body).to include("EMP001")
    end

    it "re-renders invalid submissions" do
      post "/hr/admin/employees", params: { employee_profile: { employee_code: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "updates a profile and edits a structure" do
      profile = create(:employee_profile, employee_code: "EMP009")
      structure = create(:salary_structure, user: profile.user)

      patch "/hr/admin/employees/#{profile.id}", params: { employee_profile: { designation: "Manager" } }
      expect(profile.reload.designation).to eq("Manager")

      get "/hr/admin/employees/#{profile.id}/salary_structures/#{structure.id}/edit"
      expect(response.body).to include("Edit structure")
      patch "/hr/admin/employees/#{profile.id}/salary_structures/#{structure.id}",
            params: { salary_structure: { hra: "25000" } }
      expect(structure.reload.hra).to eq(25000)
    end

    it "shows masked PII on the employee card and lists staff without profiles" do
      create(:employee_profile, pan_number: "ABCDE1234F", employee_code: "EMPX")
      create(:user, name: "No Profile Yet")
      get "/hr/admin/employees"
      expect(response.body).to include("EMPX").and include("No Profile Yet")
    end
  end

  describe "the full payroll lifecycle over HTTP" do
    before { sign_in leader }

    let!(:profile) { create(:employee_profile) }
    let!(:structure) { create(:salary_structure, user: profile.user) }

    it "create -> compute -> override -> finalize -> publish -> employee download" do
      post "/hr/admin/payroll_runs", params: { payroll_run: { period_month: "2027-06" } }
      run = HrLite::PayrollRun.last
      expect(run.period_month).to eq(month)

      post "/hr/admin/payroll_runs/#{run.id}/compute"
      expect(run.reload).to be_review
      slip = run.salary_slips.first
      expect(slip).to be_present

      # Review override: zero out LOP (full attendance).
      patch "/hr/admin/salary_slips/#{slip.id}", params: { salary_slip: { lop_override: "0" } }
      expect(slip.reload.payable_days).to eq(30)

      post "/hr/admin/payroll_runs/#{run.id}/finalize"
      expect(run.reload).to be_finalized

      post "/hr/admin/payroll_runs/#{run.id}/publish"
      expect(run.reload).to be_published

      get "/hr/admin/payroll_runs/#{run.id}/register.csv"
      expect(response.body).to include("Net pay").and include(profile.employee_code)

      # Employee side.
      sign_in profile.user
      get "/hr/salary_slips"
      expect(response.body).to include("June 2027")
      get "/hr/salary_slips/#{slip.id}"
      expect(response.body).to include("Net pay")
      get "/hr/salary_slips/#{slip.id}.pdf"
      expect(response).to redirect_to("/hr/salary_slips/#{slip.id}")
      expect(flash[:alert]).to include("PDF downloads are not configured")
    end

    it "renders the PDF through a configured render_pdf hook" do
      HrLite.config.render_pdf = ->(template:, assigns:, cache_key:) { "%PDF-fake" }
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)
      run.salary_slips.first
      run.finalize!(actor: leader)
      run.publish!(actor: leader)

      sign_in profile.user
      get "/hr/salary_slips/#{run.salary_slips.first.id}.pdf"
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to eq("%PDF-fake")
    end

    it "guards illegal transitions with an alert" do
      run = create(:payroll_run, period_month: month)
      post "/hr/admin/payroll_runs/#{run.id}/publish"
      expect(flash[:alert]).to include("not available from draft")
    end

    it "rejects overrides outside review" do
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)
      slip = run.salary_slips.first
      run.finalize!(actor: leader)

      patch "/hr/admin/salary_slips/#{slip.id}", params: { salary_slip: { lop_override: "1" } }
      expect(flash[:alert]).to include("only editable while the run is in review")
    end

    it "deletes drafts only" do
      run = create(:payroll_run, period_month: month)
      delete "/hr/admin/payroll_runs/#{run.id}"
      expect(HrLite::PayrollRun.exists?(run.id)).to be(false)

      other = create(:payroll_run, period_month: Date.new(2027, 7, 1))
      other.compute!(actor: leader)
      delete "/hr/admin/payroll_runs/#{other.id}"
      expect(HrLite::PayrollRun.exists?(other.id)).to be(true)
    end
  end

  describe "employee visibility boundaries" do
    it "hides unpublished slips and foreign slips (404, never 403)" do
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)
      slip = run.salary_slips.first

      sign_in profile.user
      get "/hr/salary_slips/#{slip.id}"
      expect(response).to have_http_status(:not_found)

      run.finalize!(actor: leader)
      run.publish!(actor: leader)
      sign_in create(:user) # someone else
      get "/hr/salary_slips/#{slip.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "shows the masked own profile page" do
      profile = create(:employee_profile, pan_number: "ABCDE1234F")
      sign_in profile.user
      get "/hr/profile"
      expect(response.body).to include("AB••••••4F")
      expect(response.body).not_to include("ABCDE1234F")
    end

    it "handles a missing profile gracefully" do
      sign_in create(:user)
      get "/hr/profile"
      expect(response.body).to include("not been set up")
    end
  end
end
