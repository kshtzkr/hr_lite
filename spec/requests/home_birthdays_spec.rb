require "rails_helper"

RSpec.describe "Birthdays this week on Home", type: :request do
  around { |example| travel_to(Date.new(2027, 2, 24).in_time_zone.change(hour: 11)) { example.run } } # Wednesday
  before { sign_in create(:user) }

  def born(name, dob, **attrs)
    create(:employee_profile, user: create(:user, name: name), date_of_birth: dob, **attrs)
  end

  it "lists this week's birthdays by day, 29 Feb on 28 Feb, never next week's or an exited colleague's" do
    born("Asha", Date.new(1990, 2, 24))
    born("Leap", Date.new(1992, 2, 29))
    born("Ravi", Date.new(1988, 3, 1)) # next Monday
    born("Gone", Date.new(1991, 2, 25), date_of_exit: Date.new(2027, 1, 1))

    get "/hr/"

    card = response.body[%r{Birthdays this week</h2>.*?</section>}m]
    expect(card).to match(/Asha.*Today.*Leap.*Sun 28 Feb/m)
    expect(card).not_to include("Ravi")
    expect(card).not_to include("Gone")
  end

  it "says so when nobody has a birthday this week" do
    get "/hr/"

    expect(response.body).to include("No birthdays this week.")
  end
end
