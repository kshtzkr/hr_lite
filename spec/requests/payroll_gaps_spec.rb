require "rails_helper"

# Screens and branches outside the happy lifecycle path.
RSpec.describe "Payroll screens and edge branches", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:month) { Date.new(2027, 6, 1) }

  before do
    HrLite.config.leadership_emails = [ "lead@x.test" ]
    sign_in leader
  end

  it "renders run index, new form, and duplicate-month errors" do
    create(:payroll_run, period_month: month)
    get "/hr/admin/payroll_runs"
    expect(response.body).to include("June 2027")

    get "/hr/admin/payroll_runs/new"
    expect(response.body).to include("New payroll run")

    post "/hr/admin/payroll_runs", params: { payroll_run: { period_month: "2027-06" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "renders the run dashboard with totals including ESI/PT deduction lines" do
    profile = create(:employee_profile)
    # Gross 17k: under the ESI ceiling; Karnataka PT slab applies too.
    create(:salary_structure, user: profile.user, basic: 12000, hra: 5000,
           special_allowance: nil, pt_state: "karnataka")
    run = create(:payroll_run, period_month: month)
    run.compute!(actor: leader)

    slip = run.salary_slips.first
    codes = slip.deductions_rows.map { |r| r["code"] }
    expect(codes).to include("esi_employee")
    expect(slip.employer_costs_hash).to include("esi_employer")
    expect(slip.published?).to be(false)

    get "/hr/admin/payroll_runs/#{run.id}"
    expect(response.body).to include("Employer cost")

    get "/hr/admin/payroll_runs/#{run.id}/register.csv"
    expect(response.body).to include("ESI").and include(profile.employee_code)
  end

  it "unlocks a finalized run" do
    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)
    run = create(:payroll_run, period_month: month)
    run.compute!(actor: leader)
    run.finalize!(actor: leader)

    post "/hr/admin/payroll_runs/#{run.id}/unlock"
    expect(run.reload).to be_review
  end

  it "shows the admin slip detail and rejects non-numeric overrides" do
    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)
    run = create(:payroll_run, period_month: month)
    run.compute!(actor: leader)
    slip = run.salary_slips.first

    get "/hr/admin/salary_slips/#{slip.id}"
    expect(response.body).to include("Tax working")

    patch "/hr/admin/salary_slips/#{slip.id}", params: { salary_slip: { lop_override: "abc" } }
    expect(flash[:alert]).to include("must be numbers")
  end

  it "renders employee profile show/new-with-user/edit screens" do
    staff = create(:user, name: "Fresh Joiner")
    get "/hr/admin/employees/new", params: { user_id: staff.id }
    expect(response.body).to include("New employee profile")

    profile = create(:employee_profile)
    get "/hr/admin/employees/#{profile.id}"
    expect(response.body).to include("Salary structures")

    get "/hr/admin/employees/#{profile.id}/edit"
    expect(response.body).to include("Edit #{profile.employee_code}")

    patch "/hr/admin/employees/#{profile.id}", params: { employee_profile: { employee_code: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "renders structure new form and re-renders invalid structure submissions" do
    profile = create(:employee_profile)
    get "/hr/admin/employees/#{profile.id}/salary_structures/new"
    expect(response.body).to include("New structure")

    post "/hr/admin/employees/#{profile.id}/salary_structures",
         params: { salary_structure: { effective_from: "2027-06-15", basic: "0" } }
    expect(response).to have_http_status(:unprocessable_entity)

    structure = create(:salary_structure, user: profile.user)
    patch "/hr/admin/employees/#{profile.id}/salary_structures/#{structure.id}",
          params: { salary_structure: { basic: "0" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "renders the built-in PDF path through the wicked seam" do
    fake_wicked = Class.new do
      def pdf_from_string(html, _opts)
        "%PDF#{html.include?('Salary slip') ? '-ok' : '-empty'}"
      end
    end
    allow(HrLite::PdfRenderer).to receive(:wicked_pdf_class).and_return(fake_wicked)

    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)
    run = create(:payroll_run, period_month: month)
    run.compute!(actor: leader)
    run.finalize!(actor: leader)
    run.publish!(actor: leader)

    sign_in profile.user
    get "/hr/salary_slips/#{run.salary_slips.first.id}.pdf"
    expect(response.body).to eq("%PDF-ok")
  end
end
