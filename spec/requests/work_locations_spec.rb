require "rails_helper"

RSpec.describe "WFH work locations", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:colleague) { create(:user, name: "Dev") }
  let(:admin) { create(:user, :admin) }
  let(:fix) { { lat: "28.5355", lng: "77.3910", accuracy_m: "20", geo_status: "ok" } }

  before { sign_in employee }

  def register(name, params = fix) = post("/hr/work_locations", params: params.merge(name: name, address: "Flat 4, Sector 18"))

  it "saves up to three homes at once, approved, the first active, and refuses a fourth" do
    %w[Home Parents Studio].each { |name| register(name) }
    mine = HrLite::WorkLocation.where(user_id: employee.id).order(:id)
    expect(mine.pluck(:status).uniq).to eq([ "approved" ])
    expect(mine.pluck(:active)).to eq([ true, false, false ])

    register("Fourth")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("at most 3 locations")
  end

  it "leaves changes to HR once three homes are saved" do
    %w[Home Parents Studio].each { |name| register(name) }
    get "/hr/work_locations"
    expect(response.body).to include(HrLite::WorkLocationsController::CAP_MESSAGE)
    expect(response.body).not_to include(">Remove<")

    studio = HrLite::WorkLocation.last
    post "/hr/work_locations/#{studio.id}/remove"
    expect(flash[:alert]).to eq(HrLite::WorkLocationsController::CAP_MESSAGE)
    expect(studio.reload).to be_approved

    sign_in admin
    get "/hr/admin/work_locations"
    expect(response.body).to include("Remove")
    post "/hr/admin/work_locations/#{studio.id}/remove"
    expect(studio.reload).to have_attributes(status: "removed", active: false)
    expect(HrLite::AuditLog.where(action: "work_location.removed", actor_id: admin.id).count).to eq(1)

    sign_in employee
    register("Fourth")
    expect(HrLite::WorkLocation.live.where(user_id: employee.id).count).to eq(3)
  end

  it "refuses a missing or vague device fix" do
    register("Home", fix.merge(lat: "", lng: ""))
    register("Home", fix.merge(accuracy_m: "800"))
    expect(HrLite::WorkLocation.count).to eq(0)
  end

  it "ignores a posted status or owner" do
    post "/hr/work_locations", params: fix.merge(name: "Home", status: "approved", user_id: colleague.id, active: true)
    expect(HrLite::WorkLocation.last).to have_attributes(user_id: employee.id, decided_by_id: nil)
  end

  it "lets HR approve a pending one (first approved becomes active) and reject with a note, never their own" do
    home, parents = %w[Home Parents].map { |n| HrLite::WorkLocation.create!(user_id: employee.id, name: n, lat: 1, lng: 1, accuracy_m: 10) }
    sign_in admin

    post "/hr/admin/work_locations/#{home.id}/approve"
    expect(home.reload).to have_attributes(status: "approved", active: true, decided_by_id: admin.id)
    post "/hr/admin/work_locations/#{parents.id}/reject"
    expect(parents.reload).to be_pending
    post "/hr/admin/work_locations/#{parents.id}/reject", params: { decision_note: "Too far from Noida" }
    expect(parents.reload).to be_rejected
    expect(HrLite::AuditLog.where(action: %w[work_location.approved work_location.rejected]).count).to eq(2)

    own = HrLite::WorkLocation.create!(user_id: admin.id, name: "Mine", lat: 1, lng: 1, accuracy_m: 10)
    post "/hr/admin/work_locations/#{own.id}/approve"
    expect(response).to have_http_status(:not_found)
  end

  it "switches the active location only to an approved one of my own" do
    register("Home")
    register("Parents")
    home, parents = HrLite::WorkLocation.order(:id).to_a
    parents.update!(status: "pending")

    post "/hr/work_locations/#{parents.id}/activate"
    expect(response).to have_http_status(:not_found)
    parents.update!(status: "approved")
    post "/hr/work_locations/#{parents.id}/activate"
    expect([ home.reload.active, parents.reload.active ]).to eq([ false, true ])

    theirs = HrLite::WorkLocation.create!(user_id: colleague.id, name: "Theirs", lat: 1, lng: 1, accuracy_m: 10, status: "approved")
    post "/hr/work_locations/#{theirs.id}/activate"
    expect(response).to have_http_status(:not_found)
  end

  it "keeps coordinates and addresses off every employee screen" do
    register("Home")
    sign_in colleague
    get "/hr/admin/work_locations"
    expect(response).to redirect_to("/hr/")
    get "/hr/team"
    expect(response.body).not_to include("28.5355")
    expect(response.body).not_to include("Sector 18")
  end
end
