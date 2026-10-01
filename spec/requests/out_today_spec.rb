require "rails_helper"

RSpec.describe "Out today on Home", type: :request do
  let(:sick) { create(:leave_type, name: "Sick leave", code: "SL") }
  let(:today) { Date.new(2027, 7, 8) } # Thursday

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }
  before { sign_in create(:user) }

  def leave(name, from, to, status: "approved")
    create(:leave_request, user: create(:user, name: name), leave_type: sick,
                           start_date: from, end_date: to, status: status)
  end

  it "lists current staff on approved leave today with their dates, never the leave type" do
    leave("Priya", today, today + 4)
    leave("Ravi", today - 2, today - 1)
    leave("Kiran", today, today, status: "pending")
    create(:employee_profile, user: leave("Gone", today, today).user, date_of_exit: today - 1)

    get "/hr/"

    expect(response.body).to include("Priya").and include("08 Jul – 12 Jul")
    expect(response.body).not_to include("Ravi")
    expect(response.body).not_to include("Kiran")
    expect(response.body).not_to include("Gone")
    expect(response.body).not_to include("Sick leave")
  end

  it "says everyone is in when nobody is on leave" do
    get "/hr/"

    expect(response.body).to include("Everyone's in today.").and include('href="/hr/team"')
  end
end
