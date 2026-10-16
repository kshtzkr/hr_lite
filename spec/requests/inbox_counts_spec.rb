require "rails_helper"

# One number for "waiting on you" everywhere, never the viewer's own request,
# and every Open lands on something the viewer can decide.
RSpec.describe "Inbox counts and own rows", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, name: "Casual", code: "CL", annual_quota: 12) }

  def badge = Nokogiri::HTML(response.body).at_css('.hrl-tabbar a[href="/hr/approvals"] .hrl-badge')&.text

  it "counts the same on overview, Home and the badge, lists no own request, and opens the item" do
    leave = create(:leave_request, user: meera, leave_type: leave_type, start_date: Date.current + 3, end_date: Date.current + 3)
    create(:regularization_request, user: meera)
    own = create(:comp_off_request, user: hr)
    sign_in hr

    get "/hr/admin/overview"
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".hrl-kpi__value").text).to eq("2")
    expect(badge).to eq("2")
    expect(page.css(".hrl-feed__item a").map { |a| a["href"] }).to include("/hr/admin/leave_requests/#{leave.id}")
    expect(response.body).not_to include("/hr/admin/comp_off_requests/#{own.id}")

    get "/hr/"
    expect(response.body).to include("2 requests waiting on you", %(href="/hr/approvals">Review requests))

    get "/hr/approvals"
    expect(response.body).to include("Casual, #{leave.date_range_label} · 1 day", %(href="/hr/admin/leave_requests/#{leave.id}"))

    get "/hr/admin/comp_off_requests"
    expect(response.body).not_to include("/hr/admin/comp_off_requests/#{own.id}")
  end

  it "keeps HR's own rows off every decision list" do
    leave = create(:leave_request, user: hr, leave_type: leave_type)
    fix = create(:regularization_request, user: hr)
    sign_in hr
    { "/hr/admin/leave_requests" => leave, "/hr/admin/regularization_requests" => fix }.each do |list, own|
      get list
      expect(response.body).not_to include("#{list}/#{own.id}")
    end
  end

  it "opens Home locations on the pending ones the badge counts" do
    HrLite::WorkLocation.create!(user_id: meera.id, name: "Parents", lat: 1, lng: 1, accuracy_m: 10)
    sign_in hr
    get "/hr/admin/work_locations"
    expect(response.body).to include("Parents")
  end

  it "counts only WFH the board lists, from today on" do
    HrLite::WfhRequest.new(user_id: meera.id, start_date: Date.current - 3, end_date: Date.current - 3, reason: "Plumber", status: "pending").save!(validate: false)
    sign_in hr
    get "/hr/admin/wfh_requests"
    expect(Nokogiri::HTML(response.body).at_css('a[href="/hr/admin/wfh_requests"] .hrl-badge')).to be_nil
  end

  it "makes the reject reason required in the form" do
    request = create(:leave_request, user: meera, leave_type: leave_type)
    sign_in hr
    get "/hr/admin/leave_requests/#{request.id}"
    expect(Nokogiri::HTML(response.body).at_css("#reject_note")["required"]).not_to be_nil
  end
end
