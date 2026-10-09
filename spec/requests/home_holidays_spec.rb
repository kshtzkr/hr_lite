require "rails_helper"

RSpec.describe "Upcoming holidays on Home", type: :request do
  let(:today) { Date.new(2027, 7, 8) } # Thursday

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }
  before { sign_in create(:user) }

  it "lists company-wide holidays in the next 60 days, not day 61 or optional ones" do
    create(:holiday, date: today + 14, name: "Bonalu")
    create(:holiday, date: today + 60, name: "Onam")
    create(:holiday, date: today + 61, name: "Diwali")
    create(:holiday, :optional, date: today + 3, name: "Rath Yatra")

    get "/hr/"

    expect(response.body).to include("Thu 22 Jul · Bonalu · in 14 days").and include("Mon 6 Sep · Onam · in 60 days")
    expect(response.body).not_to include("Diwali")
    expect(response.body).not_to include("Rath Yatra")
    expect(response.body).to include('class="hrl-card__link" href="/hr/holidays"')
  end

  it "says none are due in the next 2 months" do
    get "/hr/"

    expect(response.body).to include("No holidays in the next 2 months.")
  end
end
