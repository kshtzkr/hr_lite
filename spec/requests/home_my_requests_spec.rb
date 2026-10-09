require "rails_helper"

RSpec.describe "My requests on Home", type: :request do
  let(:user) { create(:user) }
  let(:today) { Date.new(2027, 7, 8) } # Thursday

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }
  before { sign_in user }

  it "lists my pending leave, attendance fix and comp-off" do
    leave = create(:leave_request, user: user, start_date: today + 5, end_date: today + 5)
    create(:regularization_request, user: user)
    create(:comp_off_request, user: user)

    get "/hr/"

    expect(response.body).to include("My requests").and include(%(href="/hr/leave_requests/#{leave.id}"))
    expect(response.body).to include("13 Jul · 1 day").and include("Tue 6 Jul · 10:00 – 19:00").and include("Worked Sun 4 Jul")
  end

  it "hides decided requests, other people's and the card when nothing is pending" do
    decided = %w[approved rejected cancelled].each_with_index.map do |status, i|
      create(:leave_request, user: user, status: status, start_date: today + 5 + i, end_date: today + 5 + i)
    end
    theirs = create(:leave_request, start_date: today + 5, end_date: today + 5)

    get "/hr/"

    (decided + [ theirs ]).each { |leave| expect(response.body).not_to include(%(href="/hr/leave_requests/#{leave.id}")) }
    expect(response.body).not_to include("My requests")
  end
end
