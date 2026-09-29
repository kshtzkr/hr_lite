require "rails_helper"

RSpec.describe "Adjusting a leave balance", type: :request do
  let(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Rohan") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:report) { create(:employee_profile, manager_id: manager.id).user }
  let!(:stranger) { create(:employee_profile).user }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }

  def adjust(user) = post("/hr/admin/leave_balances/adjust", params: { user_id: user.id, leave_type_id: type.id, delta: "5", note: "gift" })

  def adjustment_for(user) = HrLite::LeaveBalance.find_by(user_id: user.id, leave_type: type)&.adjustment.to_f

  describe "the guard" do
    it "is refused to a manager, even for their own report" do
      sign_in manager
      adjust(stranger)
      expect(response).to have_http_status(:not_found)
      adjust(report)
      expect(response).to have_http_status(:not_found)
      expect([ adjustment_for(stranger), adjustment_for(report) ]).to eq([ 0.0, 0.0 ])
    end

    it "works for HR" do
      sign_in hr
      adjust(stranger)
      expect(adjustment_for(stranger)).to eq(5.0)
    end

    it "shows a manager only their team's balances, and no adjust form" do
      sign_in manager
      get "/hr/admin/leave_balances"
      expect(response.body).to include(HrLite.display_name(report))
      expect(response.body).not_to include(HrLite.display_name(stranger))
      expect(response.body).not_to include("Adjust a balance")
    end
  end
end
