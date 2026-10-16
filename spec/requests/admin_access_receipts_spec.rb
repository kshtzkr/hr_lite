require "rails_helper"

# Controls that lead somewhere the viewer may go, settings findable by name,
# and the receipt an approver is asked to judge.
RSpec.describe "Admin access and receipts", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let!(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "shows New run only to those who can run payroll" do
    sign_in hr
    get "/hr/admin/payroll_runs"
    expect(response.body).not_to include("/hr/admin/payroll_runs/new")
    sign_in owner
    get "/hr/admin/payroll_runs"
    expect(response.body).to include("/hr/admin/payroll_runs/new")
  end

  it "gives the working-day settings their own HR settings tab" do
    sign_in hr
    get "/hr/admin/setting/edit"
    active = Nokogiri::HTML(response.body).at_css(".hrl-tabrow a[aria-current]")
    expect(active.text.strip).to eq("HR settings")
    get "/hr/admin/leave_types"
    expect(response.body).to include(">HR settings</a>")
  end

  describe "the receipt behind a claim" do
    let(:category) { HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false) }
    let(:pdf) { { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "cab.pdf", content_type: "application/pdf" } }

    def claim_for(user)
      HrLite::Expense.create!(user_id: user.id, category: category, amount: 1_500, spent_on: Date.current,
                              description: "Cab", receipt: pdf).tap { |e| e.submit!(actor: user) }
    end

    it "opens for the approver through a short-lived link, and is audited" do
      claim = claim_for(employee)
      sign_in finance
      get "/hr/admin/expenses"
      expect(response.body).to include(%(href="/hr/admin/expenses/#{claim.id}/receipt">Open receipt))

      get "/hr/admin/expenses/#{claim.id}/receipt"
      expect(response).to redirect_to(%r{/rails/active_storage/blobs/})
      expect(HrLite::AuditLog.where(action: "expense.receipt_viewed", actor_id: finance.id).count).to eq(1)
    end

    it "is not the approver's to open on their own claim, nor on a claim without one" do
      own = claim_for(finance)
      bare = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 900, spent_on: Date.current, description: "Bus")
      sign_in finance
      get "/hr/admin/expenses/#{own.id}/receipt"
      expect(response).to have_http_status(:not_found)
      get "/hr/admin/expenses/#{bare.id}/receipt"
      expect(response).to have_http_status(:not_found)
    end
  end
end
