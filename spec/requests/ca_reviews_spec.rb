require "rails_helper"
require Rails.root.join("../../db/migrate/20261010110100_seed_hr_lite_ca_role.rb")

RSpec.describe "CA year-end review", type: :request, no_legacy_bridge: true do
  let(:ca) { user_with_roles(HrLite::Role::CA, name: "Kapoor & Co") }
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:bells) { [] }
  let(:fy) { HrLite::FinancialYear.start_for(Date.current.prev_month) }
  let!(:slip) do
    create(:employee_profile, user: meera)
    create(:salary_structure, user: meera)
    run = create(:payroll_run)
    run.compute!(actor: owner)
    run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    run.salary_slips.sole
  end
  let!(:declaration) { HrLite::TaxDeclaration.create!(user_id: meera.id, financial_year: fy, regime: "old", status: "submitted") }

  before { HrLite.config.notify = ->(**kw) { bells << kw } }

  it "lets the CA verify a slip, flag a declaration, and HR resolve the flag" do
    sign_in ca
    get "/hr/admin/ca_reviews", params: { fy: fy }
    expect(response.body).to include("0 / 1", "Meera", "To review", "Verify all shown")
    get "/hr/admin/salary_slips/#{slip.id}"
    expect(response).to have_http_status(:ok)

    post "/hr/admin/ca_reviews/verify", params: { subject_type: "HrLite::SalarySlip", subject_id: slip.id, fy: fy }
    expect(HrLite::CaReview.find_by!(subject: slip).status).to eq("verified")

    post "/hr/admin/ca_reviews/flag", params: { subject_type: "HrLite::TaxDeclaration", subject_id: declaration.id, fy: fy, note: "" }
    expect(flash[:alert]).to start_with("Say what is wrong")
    post "/hr/admin/ca_reviews/flag", params: { subject_type: "HrLite::TaxDeclaration", subject_id: declaration.id, fy: fy,
                                                tab: "declarations", note: "No rent receipts for Jan–Mar" }
    flagged = bells.select { |b| b[:kind] == "ca.flagged" }
    expect(flagged.map { |b| b[:user] }).to include(hr)
    expect(flagged.first[:title]).to eq("CA flagged Meera's FY #{HrLite::FinancialYear.label(fy)} tax declaration")

    sign_in hr
    review = HrLite::CaReview.find_by!(subject: declaration)
    get "/hr/admin/ca_reviews", params: { fy: fy, tab: "declarations", status: "flagged" }
    expect(response.body).to include("No rent receipts", "Mark resolved")
    expect(response.body).not_to include("Flag it")
    post "/hr/admin/ca_reviews/verify", params: { subject_type: "HrLite::SalarySlip", subject_id: slip.id }
    expect(response).to redirect_to("/hr/") # HR does not verify for the CA
    post "/hr/admin/ca_reviews/#{review.id}/resolve", params: { note: "Receipts uploaded" }
    expect(review.reload).to have_attributes(status: "resolved", resolution_note: "Receipts uploaded")
    post "/hr/admin/ca_reviews/#{review.id}/resolve", params: { note: "again" }
    expect(flash[:alert]).to eq("Only a flagged item can be resolved.")
  end

  it "verifies everything shown in one go" do
    sign_in ca
    post "/hr/admin/ca_reviews/verify_all", params: { subject_type: "HrLite::TaxDeclaration", ids: [ declaration.id ] }
    post "/hr/admin/ca_reviews/verify_all", params: { subject_type: "HrLite::SalarySlip", ids: [ slip.id ] }
    expect(HrLite::CaReview.where(status: "verified").count).to eq(2)
    expect(HrLite::CaReview.outstanding(fy)).to eq("slips" => 0, "declarations" => 0, "flagged" => 0)
    get "/hr/admin/ca_reviews", params: { fy: fy, status: "unreviewed" }
    expect(response.body).to include("Nothing here.")
  end

  it "keeps CA logins out of the staff list and employees out of the review" do
    ca
    expect(HrLite.employees.map(&:id)).to include(meera.id)
    expect(HrLite.employees.map(&:id)).not_to include(ca.id)
    sign_in meera
    get "/hr/admin/ca_reviews"
    expect(response).to redirect_to("/hr/")
  end

  it "reminds the CA every March week and tells payroll on 31 March what is left" do
    ca && hr
    HrLite::CaReviewReminderJob.perform_now(on: Date.new(fy.year + 1, 2, 20)) # not March: nothing
    HrLite::CaReviewReminderJob.perform_now(on: Date.new(fy.year + 1, 3, 2))
    reminders = bells.select { |b| b[:kind] == "ca.reminder" }
    expect(reminders.map { |b| b[:user] }).to include(ca)
    expect(reminders.first[:title]).to eq("CA review: 1 slips and 1 declarations left before 31 March")

    HrLite::CaReview.flag!(slip, actor: ca, note: "TDS looks low")
    HrLite::CaReviewReminderJob.perform_now(on: Date.new(fy.year + 1, 3, 16))
    expect(bells.select { |b| b[:kind] == "ca.reminder" }.last[:title]).to end_with("before 31 March, 1 flagged")
    HrLite::CaReviewOverdueJob.perform_now(on: Date.new(fy.year + 1, 3, 31))
    expect(bells.find { |b| b[:kind] == "ca.overdue" }[:title]).to eq("CA review overdue: 1 slips, 1 declarations unverified, 1 flags open")

    HrLite::CaReview.verify!(slip, actor: ca)
    HrLite::CaReview.verify!(declaration, actor: ca)
    bells.clear
    HrLite::CaReviewReminderJob.perform_now(on: Date.new(fy.year + 1, 3, 9))
    HrLite::CaReviewOverdueJob.perform_now(on: Date.new(fy.year + 1, 3, 31))
    expect(bells).to be_empty
  end

  it "creates the CA role and gives Super Admin the review permission on an existing install" do
    owner
    super_admin = HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN)
    super_admin.role_grants.where(permission_key: "payroll.verify").delete_all
    HrLite::Role.where(name: HrLite::Role::CA).destroy_all

    SeedHrLiteCaRole.new.tap { |m| m.verbose = false }.up
    expect(HrLite::Role.find_by!(name: HrLite::Role::CA).grant_map).to include("payroll.verify" => "all", "tax.view" => "all")
    expect(super_admin.grant_map["payroll.verify"]).to eq("all")
  end
end
