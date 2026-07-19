require "rails_helper"

# Small screens and edge branches not exercised by the main flow specs.
RSpec.describe "Form screens and edge branches", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:admin) { create(:user, :admin) }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  it "renders the employee leave form" do
    sign_in create(:user)
    type
    get "/hr/leave_requests/new"
    expect(response.body).to include("Apply for leave")
  end

  it "renders leadership new/edit forms" do
    sign_in leader
    get "/hr/admin/leave_types/new"
    expect(response.body).to include("New leave type")
    get "/hr/admin/leave_types/#{type.id}/edit"
    expect(response.body).to include("Edit Casual")

    office = create(:office_location, name: "HQ")
    get "/hr/admin/office_locations/new"
    expect(response.body).to include("Add office")
    get "/hr/admin/office_locations/#{office.id}/edit"
    expect(response.body).to include("Edit HQ")
  end

  it "re-renders invalid leadership edits" do
    sign_in leader
    patch "/hr/admin/leave_types/#{type.id}", params: { leave_type: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    office = create(:office_location)
    patch "/hr/admin/office_locations/#{office.id}", params: { office_location: { lat: 999 } }
    expect(response).to have_http_status(:unprocessable_entity)

    holiday = create(:holiday)
    patch "/hr/admin/holidays/#{holiday.id}", params: { holiday: { name: "" } }
    expect(flash[:alert]).to be_present
  end

  it "shows the admin decision screen and guards double rejection" do
    sign_in admin
    workday = Date.current.next_occurring(:tuesday)
    request = create(:leave_request, leave_type: type, start_date: workday, end_date: workday)

    get "/hr/admin/leave_requests/#{request.id}"
    expect(response.body).to include("Decide")

    request.approve!(actor: admin)
    post "/hr/admin/leave_requests/#{request.id}/reject", params: { decision_note: "late" }
    expect(flash[:alert]).to include("Only pending requests")
  end
end
