require "rails_helper"

RSpec.describe "Awards admin and Home card", type: :request, no_legacy_bridge: true do
  let(:lead) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Asha") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:bells) { [] }

  before { HrLite.config.notify = ->(**kw) { bells << kw } }

  it "lets Leadership pick a winner whom everyone then sees on Home" do
    sign_in meera
    get "/hr"
    expect(response.body).not_to include("Employee of the month, quarter and year")

    sign_in lead
    get "/hr/admin/awards/new"
    post "/hr/admin/awards", params: { award: { kind: "month", period_start: Date.current, user_id: meera.id, citation: "Rebooked 12 pax" } }
    award = HrLite::Award.sole
    expect(award.period_start).to eq(Date.current.beginning_of_month)
    expect(bells.select { |b| b[:kind] == "award.won" }.map { |b| b[:user] }).to eq([ meera ])

    get "/hr/admin/awards"
    expect(response.body).to include("Employee of the month", "Meera")
    get "/hr/admin/awards/#{award.id}/edit"
    patch "/hr/admin/awards/#{award.id}", params: { award: { citation: "Rebooked 14 pax" } }
    expect(award.reload.citation).to eq("Rebooked 14 pax")

    sign_in meera
    get "/hr"
    expect(response.body).to include("Employee of the month, quarter and year", "Rebooked 14 pax")
  end

  it "says when the period already has a winner" do
    HrLite::Award.create!(user: meera, kind: "quarter", period_start: Date.current, citation: "x")
    sign_in lead
    post "/hr/admin/awards", params: { award: { kind: "quarter", period_start: Date.current, user_id: lead.id, citation: "y" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("already has a winner")
    patch "/hr/admin/awards/#{HrLite::Award.sole.id}", params: { award: { citation: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "keeps HR out" do
    sign_in user_with_roles(HrLite::Role::HR)
    get "/hr/admin/awards"
    expect(response).to redirect_to("/hr/")
  end
end
