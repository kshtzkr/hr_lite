require "rails_helper"

RSpec.describe "Leave requests", type: :request do
  let(:user) { create(:user, name: "Asha") }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
  let(:monday) { Date.new(2027, 7, 5) }

  around { |example| travel_to(Date.new(2027, 7, 1)) { example.run } }
  before { sign_in user }

  describe "employee flow" do
    it "applies for leave and sees it listed" do
      expect {
        post "/hr/leave_requests", params: {
          leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday + 1, reason: "Family" }
        }
      }.to change(HrLite::LeaveRequest, :count).by(1)

      follow_redirect!
      expect(response.body).to include("Leave request submitted.").and include("05 Jul – 06 Jul")
    end

    it "treats a blank To as a one-day request" do
      post "/hr/leave_requests", params: { leave_request: { leave_type_id: type.id, start_date: monday, end_date: "" } }
      expect(HrLite::LeaveRequest.last).to have_attributes(start_date: monday, end_date: monday)
    end

    it "pre-checks the type and fills From from the query, with Full day checked" do
      type.update!(name: "Casual leave")
      get "/hr/leave_requests/new", params: { leave_type_id: type.id, date: "2027-07-05" }
      form = Nokogiri::HTML(response.body)
      expect(form.at_css("input[name='leave_request[leave_type_id]'][value='#{type.id}']")["checked"]).to be_present
      expect(form.at_css("input[name='leave_request[start_date]']")["value"]).to eq("2027-07-05")
      expect(form.at_css("input[name='leave_request[end_date]']")["value"]).to be_nil
      expect(form.at_css("input[name='leave_request[half_day_part]'][value='']")["checked"]).to be_present
      expect(response.body).to include("Casual · 12 left")
      expect(form.css("label[for]").map { |l| l["for"] }).to all(satisfy { |id| form.at_css("##{id}") })
    end

    it "still rejects a half day that spans two dates" do
      post "/hr/leave_requests", params: {
        leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday + 1, half_day_part: "first" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("only for single-day requests")
    end

    it "keeps the probation cap and its message" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2027, 6, 1), probation_until: Date.new(2027, 11, 30))
      post "/hr/leave_requests", params: { leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday + 1 } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("During probation only 1 day of leave a month is allowed")
    end

    it "re-renders with errors on invalid input" do
      post "/hr/leave_requests", params: {
        leave_request: { leave_type_id: type.id, start_date: monday, end_date: monday - 1 }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("prevented saving")
    end

    it "shows own request but 404s a foreign one" do
      mine = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      other = create(:leave_request, leave_type: type, start_date: monday, end_date: monday)

      get "/hr/leave_requests/#{mine.id}"
      expect(response).to have_http_status(:ok)

      get "/hr/leave_requests/#{other.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "cancels a pending request" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      post "/hr/leave_requests/#{request.id}/cancel"
      expect(request.reload).to be_cancelled
    end

    it "refuses to cancel a decided past request" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      request.approve!(actor: create(:user, :admin))
      travel_to(monday + 2)
      post "/hr/leave_requests/#{request.id}/cancel"
      expect(flash[:alert]).to include("no longer")
      expect(request.reload).to be_approved
    end

    it "lists each request as one row linking to it, with the status badge" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      get "/hr/leave_requests"
      row = Nokogiri::HTML(response.body).at_css("a.hrl-listrow[href='/hr/leave_requests/#{request.id}']")
      expect(row.text.squish).to include("Casual").and include("Pending").and include("05 Jul · 1 day")
      expect(row.at_css(".hrl-badge--ok, .hrl-badge--bad")).to be_nil
    end

    it "shows a rejected request's status as a bad badge" do
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      request.reject!(actor: create(:user, :admin), note: "Busy week")
      get "/hr/leave_requests/#{request.id}"
      expect(Nokogiri::HTML(response.body).at_css(".hrl-deflist .hrl-badge--bad").text).to eq("Rejected")
    end

    it "shows balances on the index" do
      get "/hr/leave_requests"
      expect(response.body).to include("Leave balance")
    end

    it "lists colleagues on approved leave in the next 2 weeks below the form, by name and dates only" do
      sick = create(:leave_type, name: "Sick leave", code: "SL")
      away = ->(who, from, status = "approved") { create(:leave_request, user: who, leave_type: sick, start_date: from, end_date: from, status: status) }
      away.call(create(:user, name: "Priya"), monday)
      away.call(create(:user, name: "Kiran"), monday, "pending")
      away.call(user, monday)
      away.call(create(:user, name: "Later"), Date.new(2027, 7, 21))

      get "/hr/leave_requests/new"

      card = Nokogiri::HTML(response.body).css("section.hrl-card").last.text
      expect(card).to include("Out in the next 2 weeks").and include("Priya").and include("05 Jul")
      expect(card).not_to include("Kiran")
      expect(card).not_to include("Asha")
      expect(card).not_to include("Later")
      expect(card).not_to include("Sick leave")
      expect(response.body.index("Out in the next 2 weeks")).to be > response.body.index("Submit request")
    end
  end

  describe "balances page" do
    it "says Credited on the comp-off card, Entitled on the others, each with an Apply link for its type" do
      type
      comp = create(:leave_type, name: "Comp off", comp_off: true, annual_quota: 0)
      get "/hr/leave_balances", params: { year: 2027 }
      cards = Nokogiri::HTML(response.body).css("section.hrl-card")
      expect(cards.to_h { |card| [ card.at_css("h2").text, card.at_css("dt").text ] })
        .to eq("Casual" => "Entitled", "Comp off" => "Credited")
      expect(cards.map { |card| card.at_css("a.hrl-card__link")["href"] })
        .to match_array([ type, comp ].map { |t| "/hr/leave_requests/new?leave_type_id=#{t.id}" })
    end

    it "shows an empty state, not a bare title, when no paid type is set up" do
      create(:leave_type, paid: false)
      get "/hr/leave_balances"
      expect(response.body).to include("No leave types set up yet. Ask HR.")
      expect(response.body).not_to include("hrl-deflist")
    end
  end

  describe "holidays + calendar pages" do
    it "lists holidays for the year" do
      create(:holiday, date: Date.new(2027, 3, 4), name: "Holi 2027")
      get "/hr/holidays", params: { year: 2027 }
      expect(response.body).to include("Holi 2027")
    end

    it "mutes past holidays, badges only the next one and voids empty cells" do
      %w[2027-03-04 2027-08-15 2027-10-02].each { |d| create(:holiday, date: Date.parse(d), name: "H #{d}") }
      get "/hr/holidays"
      rows = Nokogiri::HTML(response.body).css("tbody tr")
      expect(rows.map { |r| r["class"] }).to eq([ "hrl-muted", nil, nil ])
      expect(rows.map { |r| r.at_css("td.hrl-cell--void").present? }).to eq([ true, false, true ])
      expect(rows[1].text).to include("Next")
    end

    it "lists the month's holidays and colleagues on leave in the agenda, without the leave type" do
      create(:holiday, date: monday, name: "Founders day")
      colleague = create(:user, name: "Dev Kumar")
      create(:leave_request, :approved, user: colleague, leave_type: create(:leave_type, name: "Sick", code: "SICKQ"),
             start_date: monday + 1, end_date: monday + 1)

      get "/hr/calendar", params: { month: "2027-07" }
      agenda = Nokogiri::HTML(response.body).css(".hrl-feed__item").map(&:text)
      expect(agenda).to eq([ "Mon 5 Jul: Founders day (holiday)", "Tue 6 Jul: Dev Kumar, on leave" ])
      expect(response.body).to include("1 off</span>").and include("N off On leave</span>")
      expect(response.body).not_to include("SICKQ")
      expect(response.body).not_to include('style="color:')
    end
  end
end
