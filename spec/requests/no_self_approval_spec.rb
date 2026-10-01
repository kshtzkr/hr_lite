require "rails_helper"

# Team and company scope both include the approver, and Document#readable_by?
# always admits the owner. Without an explicit exclusion a manager approved
# their own leave, Finance approved its own expense claims, and HR verified
# its own papers.
RSpec.describe "Nobody decides their own request", type: :request do
  let(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  it "refuses a manager approving their own leave" do
    leave_type = create(:leave_type, code: "CL", name: "Casual", annual_quota: 12)
    leave = create(:leave_request, user: manager, leave_type: leave_type,
                                   start_date: Date.current + 8, end_date: Date.current + 8)
    sign_in manager

    post "/hr/admin/leave_requests/#{leave.id}/approve"

    expect(leave.reload).not_to be_approved
  end

  it "refuses Finance approving its own expense claim" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    claim = HrLite::Expense.create!(user_id: finance.id, category: category, amount: 1_500,
                                    spent_on: Date.current, description: "Cab")
    claim.submit!(actor: finance)
    sign_in finance

    post "/hr/admin/expenses/#{claim.id}/approve"

    expect(claim.reload.status).not_to eq("approved")
  end

  it "refuses HR verifying its own document" do
    doc = HrLite::Document.create!(user_id: hr.id, category: "offer_letter", title: "Offer letter",
                                   file: { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "scan.pdf",
                                           content_type: "application/pdf" })
    sign_in hr

    post "/hr/admin/documents/#{doc.id}/verify"

    expect(doc.reload.verification).not_to eq("verified")
  end
end
