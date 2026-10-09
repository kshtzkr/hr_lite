require "rails_helper"

RSpec.describe "On leave this week on Home", type: :request do
  let(:sick) { create(:leave_type, name: "Sick leave", code: "SL") }
  let(:today) { Date.new(2027, 7, 8) } # Thursday

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }
  before { sign_in create(:user) }

  def leave(name, from, to, status: "approved")
    create(:leave_request, user: create(:user, name: name), leave_type: sick,
                           start_date: from, end_date: to, status: status)
  end

  it "lists current staff on approved leave this week with their dates, never the leave type" do
    leave("Priya", today, today + 4)
    leave("Ravi", today - 7, today - 6)
    leave("Kiran", today, today, status: "pending")
    create(:employee_profile, user: leave("Gone", today, today).user, date_of_exit: today - 1)

    get "/hr/"

    expect(response.body).to include("Priya").and include("08 Jul – 12 Jul")
    expect(response.body).to include('title="On leave: 08 Jul – 12 Jul"')
    expect(response.body).not_to include("Ravi")
    expect(response.body).not_to include("Kiran")
    expect(response.body).not_to include("Gone")
    # The viewer's own balance chip names the type; the week card must not.
    expect(response.body[%r{On leave this week</h2>.*?</section>}m]).not_to include("Sick leave")
  end

  it "shows the leave's dates on the team board, visibly and on hover over the name" do
    leave("Priya", today - 1, today + 1)

    get "/hr/team"

    expect(response.body).to include("07 Jul – 09 Jul").and include('title="On leave: 07 Jul – 09 Jul"')
  end

  context "on Monday" do
    let(:today) { Date.new(2027, 7, 5) }

    it "lists a colleague on leave Thursday but not one on leave next week" do
      leave("Priya", today + 3, today + 3)
      leave("Ravi", today + 7, today + 8)

      get "/hr/"

      expect(response.body).to include("Priya")
      expect(response.body).not_to include("Ravi")
    end
  end

  it "says nobody is on leave this week, never that everyone is in" do
    get "/hr/"

    expect(response.body).to include("Nobody is on leave this week.").and include('class="hrl-card__link" href="/hr/team"')
    expect(response.body).not_to include("in today")
  end
end
