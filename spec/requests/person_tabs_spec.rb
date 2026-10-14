require "rails_helper"

# One person's records as tabs: every tab shown opens, and nobody sees a tab
# for a record their reach does not cover.
RSpec.describe "Person tabs", type: :request do
  let(:person) { create(:employee_profile).user }

  before { HrLite.config.office_geofence = true }

  def record_tabs(path)
    get path
    Nokogiri::HTML(response.body).css('nav.hrl-tabrow[aria-label$="records"] a').map { |a| a["href"] }
  end

  [ HrLite::Role::HR, HrLite::Role::LEADERSHIP, HrLite::Role::SUPER_ADMIN ].each do |role|
    it "opens every record tab a #{role} is shown for one person" do
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, role)
      hrefs = record_tabs("/hr/people/#{person.id}/timeline")
      expect(hrefs.size).to be > 1
      aggregate_failures do
        hrefs.each do |href|
          get href
          expect(response).to have_http_status(:ok), "#{role}: #{href} answered #{response.status}"
        end
      end
    end
  end

  it "shows a colleague, or a manager who is not theirs, no record tabs" do
    [ HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER ].each do |role|
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, role)
      expect(record_tabs("/hr/people/#{person.id}/timeline")).to be_empty
    end
  end
end
