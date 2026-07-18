require "rails_helper"

RSpec.describe "Admin overview", type: :request do
  let(:admin) { create(:user, :admin) }

  it "is admin-gated" do
    sign_in create(:user)
    get "/hr/admin/overview"
    expect(response).to redirect_to("/hr/")
  end

  it "shows the quiet-day state" do
    sign_in admin
    get "/hr/admin/overview"
    expect(response.body).to include("All present and accounted for")
  end

  it "surfaces pending, out-today, flagged and missing-checkout sections" do
    travel_to(Date.new(2027, 7, 6)) do
      type = create(:leave_type, name: "Casual", annual_quota: 12)
      create(:leave_request, :approved, user: create(:user, name: "Outta Office"), leave_type: type,
             start_date: Date.new(2027, 7, 6), end_date: Date.new(2027, 7, 7))
      create(:leave_request, user: create(:user, name: "Pending Person"), leave_type: type,
             start_date: Date.new(2027, 7, 9), end_date: Date.new(2027, 7, 9))
      create(:attendance_record, :checked_in, :flagged, user: create(:user, name: "Flagged Fred"),
             date: Date.new(2027, 7, 6))
      create(:attendance_record, user: create(:user, name: "Forgot Fatima"), date: Date.new(2027, 7, 5),
             check_in_at: Time.zone.parse("2027-07-05 09:00"))

      sign_in admin
      get "/hr/admin/overview"
      expect(response.body).to include("Outta Office").and include("Pending Person")
        .and include("Flagged Fred").and include("Forgot Fatima")
    end
  end
end
