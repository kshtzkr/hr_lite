require "rails_helper"

# Inbox › All: everything the viewer can decide, in one list, with one count.
RSpec.describe "Inbox", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "lists what HR can decide, never HR's own, and counts it on the menu" do
    create(:comp_off_request, user: meera)
    create(:comp_off_request, user: hr)
    sign_in hr
    get "/hr/approvals"
    page = Nokogiri::HTML(response.body)
    expect(page.css("tbody tr").map { |tr| tr.css("td").first(2).map { |td| td.text.strip } }).to eq([ [ "Comp-off", "Meera" ] ])
    expect(page.at_css('tbody a.hrl-btn')["href"]).to eq("/hr/admin/comp_off_requests")
    expect(page.at_css('.hrl-tabbar a[href="/hr/approvals"] .hrl-badge').text).to eq("1")
  end

  it "keeps Inbox off the menu for someone with nothing to decide" do
    sign_in meera
    get "/hr/"
    expect(response.body).not_to include('href="/hr/approvals"')
    get "/hr/approvals"
    expect(response.body).to include("Nothing is waiting on you.")
  end
end
