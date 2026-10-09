require "rails_helper"
require Rails.root.join("../../db/migrate/20261010100500_grant_hr_lite_tax_to_hr.rb")

RSpec.describe "Tax, worked out live", type: :request, no_legacy_bridge: true do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:profile) { create(:employee_profile, user: employee) }
  let(:pdf) { Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 receipt"), "application/pdf", original_filename: "rent.pdf") }

  before do
    create(:salary_structure, user: employee, effective_from: HrLite::FinancialYear.start_for(Date.current),
                              basic: 50_000, hra: 20_000, special_allowance: 30_000)
  end

  def submit_with_rent
    patch "/hr/tax_declaration", params: { submit_to_hr: "1", tax_declaration: { regime: "old", tax_declaration_items_attributes: {
      "0" => { section: "hra", declared_amount: "240000", landlord_pan: "abcde1234f", proofs: [ pdf ] },
      "1" => { section: "80c", declared_amount: "200000" }
    } } }
    HrLite::TaxDeclaration.find_by!(user_id: employee.id)
  end

  it "shows the employee both regimes and re-works the tax on what is typed, saving nothing" do
    sign_in employee
    get "/hr/tax_declaration"
    expect(response.body).to include("New regime", "Old regime", "TDS a month", "How the new regime tax is worked out")

    post "/hr/tax_declaration/preview", params: { tax_declaration: { regime: "old", tax_declaration_items_attributes: {
      "0" => { section: "80c", declared_amount: "999999" }
    } } }
    expect(response.body).to include("Old regime", "limit ₹1,50,000")
    expect(response.body).not_to include("<html")
    expect(HrLite::TaxDeclaration.count).to eq(0)
  end

  it "takes proof with the claim, and HR opens it, accepts it all and payroll uses the capped amounts" do
    sign_in employee
    declaration = submit_with_rent
    expect(declaration).to be_submitted
    rent = declaration.tax_declaration_items.find_by!(section: "hra")
    expect([ rent.landlord_pan, rent.proofs.sole.filename.to_s ]).to eq([ "ABCDE1234F", "rent.pdf" ])

    get "/hr/admin/tax_declarations/#{declaration.id}/proofs/#{rent.proofs.sole.id}"
    expect(response).to redirect_to("/hr/") # an employee is not HR

    sign_in hr
    get "/hr/admin/tax_declarations/#{declaration.id}"
    expect(response.body).to include("Open rent.pdf", "No proof attached", "landlord PAN ABCDE1234F", "How the old regime tax is worked out")
    get "/hr/admin/tax_declarations/#{declaration.id}/proofs/#{rent.proofs.sole.id}"
    expect(response.location).to include("/rails/active_storage/blobs/")
    expect(HrLite::AuditLog.where(action: "tax_proof.downloaded").count).to eq(1)
    get "/hr/admin/tax_declarations/#{declaration.id}/proofs/0"
    expect(response).to have_http_status(:not_found)

    post "/hr/admin/tax_declarations/#{declaration.id}/accept_all"
    expect(declaration.reload).to be_verified
    expect(declaration.old_regime_deductions(structure: HrLite::SalaryStructure.sole)).to eq(330_000) # HRA 1,80,000 (rent − 10% of Basic, non-metro) + 80C 1,50,000
    post "/hr/admin/tax_declarations/#{declaration.id}/accept_all"
    expect(flash[:alert]).to eq("Only a submitted declaration can be accepted.")
  end

  it "lists everyone's tax for HR, filed or not" do
    create(:employee_profile, user: create(:user, name: "No Structure"))
    sign_in hr
    get "/hr/admin/tax_declarations/overview"
    expect(response.body).to include("Meera", "Not filed", "No salary structure")

    get "/hr/admin/tax_declarations/people/#{employee.id}"
    expect(response.body).to include("How the old regime tax is worked out", "No declaration filed this year")
  end

  it "grants HR the tax screens on an install that already has its roles" do
    role = HrLite::Role.find_by!(name: HrLite::Role::HR)
    role.role_grants.where(permission_key: %w[tax.view tax.manage]).delete_all
    GrantHrLiteTaxToHr.new.tap { |m| m.verbose = false }.up
    expect(role.role_grants.reload.where(permission_key: %w[tax.view tax.manage]).pluck(:scope)).to eq(%w[all all])
  end
end
