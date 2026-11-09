require "rails_helper"

# HR and leadership tap a day on the company calendar to make it, or stop it
# being, a holiday for every office. Everyone else sees the calendar as before.
RSpec.describe "Holidays from the company calendar", type: :request do
  let(:day) { Date.current + 1 }
  let(:month) { day.strftime("%Y-%m") }

  def page = Nokogiri::HTML(response.body)

  [ HrLite::Role::HR, HrLite::Role::LEADERSHIP ].each do |role|
    it "lets #{role} tap a day and make it a holiday for every office, back on that month" do
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, role)
      get "/hr/calendar", params: { month: month, day: day.iso8601 }
      expect(page.css(".hrl-mgrid__num a").size).to eq(day.end_of_month.day)
      expect(page.at_css("#calendar-day form")["action"]).to eq("/hr/admin/holidays?from=calendar")

      post "/hr/admin/holidays?from=calendar", params: { holiday: { date: day.iso8601, name: "Diwali" } }
      expect(response).to redirect_to("/hr/calendar?month=#{month}")
      expect(HrLite::Holiday.find_by!(name: "Diwali")).to have_attributes(date: day, office_location_id: nil, optional: false)
    end
  end

  [ HrLite::Role::MANAGER, HrLite::Role::EMPLOYEE ].each do |role|
    it "shows #{role} the plain calendar and refuses their writes" do
      holiday = create(:holiday, date: day)
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, role)
      get "/hr/calendar", params: { month: month, day: day.iso8601 }
      expect(page.css(".hrl-mgrid__num a, #calendar-day")).to be_empty

      post "/hr/admin/holidays?from=calendar", params: { holiday: { date: (day + 1).iso8601, name: "Sneaky" } }
      delete "/hr/admin/holidays/#{holiday.id}?from=calendar"
      expect(HrLite::Holiday.pluck(:id)).to eq([ holiday.id ])
    end
  end

  describe "as leadership" do
    let(:lead) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP) }

    before { sign_in lead }

    it "removes that day's penalties with the reason and leaves other days' alone" do
      meera = create(:user)
      penalty = lambda do |date|
        record = create(:attendance_record, user: meera, date: date)
        HrLite::AttendancePenalty.create!(user_id: meera.id, attendance_record: record, date: date, minutes: 30, reason: "late")
      end
      hit, other = penalty.(Date.current), penalty.(Date.current - 1)

      post "/hr/admin/holidays", params: { holiday: { date: Date.current.iso8601, name: "Diwali" } }
      expect(hit.reload).to have_attributes(removed_by_id: lead.id, removal_reason: "Holiday declared: Diwali")
      expect(hit.removed_at).to be_present
      expect(other.reload.removed_at).to be_nil
    end

    it "asks, then tells everyone a removed holiday is a working day; a past one has no Remove" do
      holiday = create(:holiday, date: day, name: "Diwali")
      get "/hr/calendar", params: { month: month, day: day.iso8601 }
      expect(page.at_css("#calendar-day form")["data-turbo-confirm"])
        .to eq("Remove Diwali? #{day.strftime('%a %-d %b %Y')} becomes a working day and everyone is told.")

      titles = []
      allow(HrLite::Notifications).to receive(:publish) { |_event, **opts| titles << opts[:title] }
      delete "/hr/admin/holidays/#{holiday.id}?from=calendar"
      expect(response).to redirect_to("/hr/calendar?month=#{month}")
      expect(titles).to include("Holiday removed: Diwali on #{day.strftime('%a %d %b %Y')}. It is a working day.")

      past = create(:holiday, date: Date.current - 1, name: "Old")
      get "/hr/calendar", params: { month: past.date.strftime("%Y-%m"), day: past.date.iso8601 }
      expect(page.at_css("#calendar-day").text).to include("Old")
      expect(page.at_css("#calendar-day form")).to be_nil
    end
  end
end
