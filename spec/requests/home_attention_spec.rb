require "rails_helper"

RSpec.describe "Home needs attention", type: :request do
  let(:user) { create(:user) }
  let(:today) { Date.new(2027, 7, 8) } # Thursday; Sat 3 and Sun 4 Jul are the weekend

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }
  before { sign_in user }

  def fix_href(date) = "/hr/regularization_requests/new?date=#{date.iso8601}"

  it "lists last week's absent, open and flagged days with a Fix link" do
    create(:attendance_record, user: user, date: today - 7, check_in_at: (today - 7).in_time_zone.change(hour: 9))
    create(:attendance_record, user: user, date: today - 6, flagged: true, flag_note: "Outside office",
                               check_in_at: (today - 6).in_time_zone.change(hour: 9), check_out_at: (today - 6).in_time_zone.change(hour: 18))

    get "/hr/"

    expect(response.body).to include("Mon 5 Jul · Absent").and include(fix_href(today - 3))
    expect(response.body).to include("Needs a fix")
    expect(response.body).to include("Thu 1 Jul · No check-out").and include("Fri 2 Jul · Flagged")
    expect(response.body).to include("Apply leave").and include("Fix a punch").and include("Payslip")
  end

  it "skips weekends, worked holidays, today, last night's open shift, days with a pending ticket and days over a week ago" do
    create(:holiday, date: today - 2)
    create(:attendance_record, user: user, date: today - 2, flagged: true, flag_note: "Outside office",
                               check_in_at: (today - 2).in_time_zone.change(hour: 9))
    create(:attendance_record, user: user, date: today - 1, check_in_at: (today - 1).in_time_zone.change(hour: 22))
    create(:regularization_request, user: user, date: today - 3)

    get "/hr/"

    [ today - 5, today - 4, today - 3, today - 2, today - 1, today, today - 8 ].each do |date|
      expect(response.body).not_to include(fix_href(date))
    end
  end

  it "skips days before the employee joined" do
    create(:employee_profile, user: user, date_of_joining: today)

    get "/hr/"

    expect(response.body).not_to include(fix_href(today - 3))
    expect(response.body).not_to include("Needs a fix")
  end
end
