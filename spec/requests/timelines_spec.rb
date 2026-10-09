require "rails_helper"

RSpec.describe "Timelines", type: :request, no_legacy_bridge: true do
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:dev) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }

  before do
    create(:employee_profile, user: meera, designation: "Executive", date_of_joining: Date.new(Date.current.year, 1, 2))
    HrLite::PerformancePlan.create!(user: meera, start_date: Date.current - 5, end_date: Date.current + 25, goals: "Ship it")
  end

  it "shows a colleague the public story only, linked from the org chart" do
    sign_in dev
    get "/hr/org"
    expect(response.body).to include(%(href="/hr/people/#{meera.id}/timeline"))

    get "/hr/people/#{meera.id}/timeline"
    expect(response.body).to include("Meera", "Executive", "Joined")
    expect(response.body).not_to include("Performance improvement plan")
  end

  it "shows the employee their own private rows, and walks years" do
    sign_in meera
    get "/hr/timeline"
    expect(response.body).to include("Performance improvement plan started", "Private")

    get "/hr/timeline", params: { year: Date.current.year - 1 }
    expect(response.body).to include("Nothing on the timeline for #{Date.current.year - 1}")
  end

  it "404s for someone who is not an employee" do
    sign_in dev
    get "/hr/people/0/timeline"
    expect(response).to have_http_status(:not_found)
  end
end
