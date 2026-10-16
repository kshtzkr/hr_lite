require "rails_helper"

# Second security pass (2026-10-16): self-edits, expiring file links and the
# audit trail. Each example is the refusal, the redaction or the row.
RSpec.describe "Security audit 2", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:boss) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }

  def pdf = { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "scan.pdf", content_type: "application/pdf" }
  def actions = HrLite::AuditLog.pluck(:action)

  it "404s HR editing, re-paying or offboarding their own profile (SE-1)" do
    own = create(:employee_profile, user: hr, permanent_wfh: false)
    sign_in hr

    patch "/hr/admin/employees/#{own.id}", params: { employee_profile: { permanent_wfh: "1" } }
    expect(response).to have_http_status(:not_found)
    get "/hr/admin/employees/#{own.id}/salary_structures/new"
    expect(response).to have_http_status(:not_found)
    post "/hr/admin/employees/#{own.id}/offboard"
    expect(response).to have_http_status(:not_found)
    expect(own.reload).to have_attributes(permanent_wfh: false, date_of_exit: nil)
  end

  it "hands HR a tax-proof link that dies after five minutes (SE-5)" do
    declaration = HrLite::TaxDeclaration.create!(user_id: employee.id, regime: "old",
                                                 financial_year: HrLite::FinancialYear.start_for(Date.current))
    item = declaration.tax_declaration_items.create!(section: "80c", declared_amount: BigDecimal("150000"))
    item.proofs.attach(pdf)
    sign_in hr

    get "/hr/admin/tax_declarations/#{declaration.id}/proofs/#{item.proofs.sole.id}"
    link = response.location
    travel(6.minutes) { get link }
    expect(response).to have_http_status(:not_found)
  end

  it "serves the ID-card photo on a link that expires (SE-6)" do
    profile = create(:employee_profile, user: employee)
    profile.photo.attach(io: StringIO.new("\x89PNG\r\n\x1A\n".b), filename: "me.png", content_type: "image/png")
    sign_in employee

    get "/hr/id_card"
    src = response.body[%r{/rails/active_storage/blobs/proxy/[^"]+}]
    travel(2.hours) { get src }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps a date of birth and help-desk text out of the audit trail (SE-10)" do
    profile = create(:employee_profile, user: employee)
    profile.update!(date_of_birth: Date.new(1990, 4, 12))
    request = HrLite::HrRequest.create!(user: employee, category: "bank_change", subject: "New account at HDFC", body: "Account 99887766")

    trail = HrLite::AuditLog.where(subject_id: [ profile.id, request.id ]).pluck(:audited_changes)
    expect(trail.to_s).not_to include("1990", "HDFC", "99887766")
    expect(trail.to_s).to include("[changed]")
  end

  it "files an 'Aadhaar' or ' PAN ' upload in the money tier, whatever the case (SE-13)" do
    docs = [ "Aadhaar", " PAN " ].map { |category| HrLite::Document.create!(user_id: employee.id, category: category, title: "ID", file: pdf) }
    expect(docs.map(&:visibility)).to eq(%w[money money])
  end

  it "mentions employees in kudos, never an outside login (SE-14)" do
    ca = user_with_roles(HrLite::Role::CA, name: "Outside CA")
    kudo = create(:kudo, giver: hr, message: "Thanks @[Meera](#{employee.id}) @[CA](#{ca.id})")

    expect(kudo.register_mentions!).to eq([ employee ])
  end

  it "takes away everything but the Employee role on offboarding (SE-15)" do
    leaver = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::FINANCE, name: "Leaver")
    profile = create(:employee_profile, user: leaver)
    sign_in hr

    post "/hr/admin/employees/#{profile.id}/offboard"
    expect(HrLite::RoleAssignment.for_user(leaver).map { |a| a.role.name }).to eq([ HrLite::Role::EMPLOYEE ])
  end
end
