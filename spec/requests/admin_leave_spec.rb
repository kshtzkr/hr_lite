require "rails_helper"

RSpec.describe "Admin leave management", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:employee) { create(:user, name: "Asha") }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
  let(:monday) { Date.new(2027, 7, 5) }

  around { |example| travel_to(Date.new(2027, 7, 1)) { example.run } }

  describe "authorization" do
    it "blocks employees from approvals and balances" do
      sign_in employee
      get "/hr/admin/leave_requests"
      expect(response).to redirect_to("/hr/")
      post "/hr/admin/leave_balances/adjust", params: { user_id: employee.id }
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "approvals" do
    before { sign_in admin }

    let!(:request_row) do
      create(:leave_request, user: employee, leave_type: type, start_date: monday, end_date: monday)
    end

    it "lists by status with pending default" do
      get "/hr/admin/leave_requests"
      expect(response.body).to include("Asha")

      get "/hr/admin/leave_requests", params: { status: "approved" }
      expect(response.body).to include("No approved requests")
    end

    it "approves from the decision screen" do
      post "/hr/admin/leave_requests/#{request_row.id}/approve"
      expect(request_row.reload).to be_approved
      expect(flash[:notice]).to eq("Leave approved.")
    end

    it "requires a note to reject" do
      post "/hr/admin/leave_requests/#{request_row.id}/reject", params: { decision_note: "" }
      expect(request_row.reload).to be_pending

      post "/hr/admin/leave_requests/#{request_row.id}/reject", params: { decision_note: "Peak week" }
      expect(request_row.reload).to be_rejected
    end

    it "reports an unapprovable request (balance drained)" do
      tight = create(:leave_type, annual_quota: 1)
      first = create(:leave_request, user: employee, leave_type: tight, start_date: monday + 1, end_date: monday + 1)
      second = create(:leave_request, user: employee, leave_type: tight, start_date: monday + 2, end_date: monday + 2)
      first.approve!(actor: admin)

      post "/hr/admin/leave_requests/#{second.id}/approve"
      expect(second.reload).to be_pending
      expect(flash[:alert]).to include("balance no longer covers")
    end

    it "rejects double decisions politely" do
      post "/hr/admin/leave_requests/#{request_row.id}/approve"
      post "/hr/admin/leave_requests/#{request_row.id}/approve"
      expect(flash[:alert]).to include("Only pending requests")
    end
  end

  describe "balance matrix + adjustment" do
    before { sign_in admin }

    it "renders the team matrix" do
      type
      employee
      get "/hr/admin/leave_balances", params: { year: 2027 }
      expect(response.body).to include("Asha")
    end

    it "adjusts with a note and audits" do
      type # materialize the audited leave type outside the counted block
      expect {
        post "/hr/admin/leave_balances/adjust", params: {
          user_id: employee.id, leave_type_id: type.id, year: 2027, delta: "1.5", note: "Comp off for Sunday sale"
        }
      }.to change(HrLite::AuditLog, :count).by(1)

      balance = HrLite::LeaveBalance.for(employee, type, 2027)
      expect(balance.adjustment).to eq(BigDecimal("1.5"))
      expect(balance.adjustment_note).to include("Comp off")
    end

    it "requires a note and a valid number" do
      post "/hr/admin/leave_balances/adjust", params: {
        user_id: employee.id, leave_type_id: type.id, year: 2027, delta: "1", note: ""
      }
      expect(flash[:alert]).to include("note is required")

      post "/hr/admin/leave_balances/adjust", params: {
        user_id: employee.id, leave_type_id: type.id, year: 2027, delta: "abc", note: "x"
      }
      expect(flash[:alert]).to include("valid adjustment")
    end
  end
end
