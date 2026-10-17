require "rails_helper"

# One number for "waiting on you" everywhere, never the viewer's own request,
# and every Open lands on something the viewer can decide.
RSpec.describe "Inbox counts and own rows", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, name: "Chitra") }
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, name: "Casual", code: "CL", annual_quota: 12) }

  def badge = Nokogiri::HTML(response.body).at_css('.hrl-tabbar a[href="/hr/approvals"] .hrl-badge')&.text

  it "counts the same on overview, Home and the badge, lists no own request, and opens the item" do
    leave = create(:leave_request, user: meera, leave_type: leave_type, start_date: Date.current.next_occurring(:wednesday), end_date: Date.current.next_occurring(:wednesday))
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

  it "names WFH by its dates and sends a home location to its list" do
    wfh = HrLite::WfhRequest.new(user_id: meera.id, start_date: Date.current + 1, end_date: Date.current + 1, reason: "Plumber", status: "pending")
    wfh.save!(validate: false)
    HrLite::WorkLocation.create!(user_id: meera.id, name: "Parents", lat: 1, lng: 1, accuracy_m: 10)
    sign_in hr
    get "/hr/approvals"
    expect(response.body).to include("WFH, #{wfh.dates_label}", %(href="/hr/admin/wfh_requests/#{wfh.id}"), %(href="/hr/admin/work_locations">Open))
  end

  it "names a claim by category, amount and date" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    claim = HrLite::Expense.create!(user_id: meera.id, category: category, amount: 1_500, spent_on: Date.new(2026, 10, 14), description: "Cab")
    claim.submit!(actor: meera)
    sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::FINANCE, name: "Fin")
    get "/hr/approvals"
    expect(response.body).to include("Claim: Travel, ₹1,500.00, Wed 14 Oct")
  end

  it "puts a pending resignation in the Inbox and the Home count, opening the person" do
    leader = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP, name: "Asha")
    profile = create(:employee_profile, user: meera)
    HrLite::Resignation.create!(user: meera, proposed_last_day: Date.new(2026, 11, 15))
    sign_in leader
    get "/hr/approvals"
    expect(response.body).to include("Resignation, last day 15 Nov 2026", %(href="/hr/admin/employees/#{profile.id}"))
    get "/hr/"
    expect(response.body).to include("1 request waiting on you")
  end

  it "opens the viewer's own requests on their own pages from their This week screen" do
    travel_to((Date.current.beginning_of_week + 2).noon) do # a Wednesday: leave cannot sit on a weekly off
      leave = create(:leave_request, user: hr, leave_type: leave_type, start_date: Date.current, end_date: Date.current)
      sign_in hr
      get "/hr/admin/attendances/#{hr.id}/summary"
      expect(response.body).to include(%(href="/hr/leave_requests/#{leave.id}"))
      expect(response.body).not_to include("/hr/admin/leave_requests/#{leave.id}")
    end
  end

  it "makes the reject reason required in the form" do
    request = create(:leave_request, user: meera, leave_type: leave_type)
    sign_in hr
    get "/hr/admin/leave_requests/#{request.id}"
    expect(Nokogiri::HTML(response.body).at_css("#reject_note")["required"]).not_to be_nil
  end
end
