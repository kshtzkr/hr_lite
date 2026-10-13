require "rails_helper"

RSpec.describe "Linking a meeting to a CRM lead", type: :request do
  let(:asha) { create(:user, name: "Asha") }
  let(:admin) { create(:user, :admin) }
  let(:leads) { { "41" => "Rahul Mehta · Bali", "42" => "Neha Rao · Ladakh" } }

  before do
    HrLite.config.office_geofence = true
    HrLite.config.crm_search = ->(_user, q) { leads.select { |_, l| l.downcase.include?(q.downcase) }.map { |id, l| { id: id, label: l } } }
    HrLite.config.crm_find = ->(id) { leads[id.to_s] && { label: leads[id.to_s], url: "/leads/#{id}" } }
    travel_to(Time.zone.local(2026, 10, 20, 11, 0))
    record = create(:attendance_record, user: asha, date: Date.current, check_in_at: 2.hours.ago)
    HrLite::WorkModeEvent.start!(user_id: asha.id, mode: "office", source: "system", attendance_record: record)
    sign_in asha
  end

  after { travel_back }

  it "searches leads as you type, needing two letters" do
    get "/hr/work_mode/crm_search", params: { q: "r" }
    expect(response.parsed_body).to eq([])
    get "/hr/work_mode/crm_search", params: { q: "rah" }
    expect(response.parsed_body).to eq([ { "id" => "41", "label" => "Rahul Mehta · Bali" } ])
  end

  it "links a client meeting to a lead, filling the client, and HR's timeline links to it" do
    post "/hr/work_mode", params: { mode: "outside_meeting", title: "Proposal", crm_ref: "41" }
    event = HrLite::WorkModeEvent.last
    expect(event).to have_attributes(mode: "outside_meeting", crm_ref: "41", client: "Rahul Mehta · Bali")

    sign_in admin
    get "/hr/admin/work_modes", params: { user_id: asha.id }
    expect(response.body).to include(%(href="/leads/41")).and include("Lead: Rahul Mehta")
  end

  it "refuses a lead that does not exist" do
    post "/hr/work_mode", params: { mode: "outside_meeting", title: "Proposal", crm_ref: "999" }
    expect(flash[:alert]).to eq("That lead was not found.")
  end

  it "returns nothing when the host has no CRM" do
    HrLite.config.crm_search = nil
    get "/hr/work_mode/crm_search", params: { q: "rahul" }
    expect(response.parsed_body).to eq([])
  end
end
