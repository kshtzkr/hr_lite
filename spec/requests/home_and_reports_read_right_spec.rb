require "rails_helper"

# HRMS audit lane F1: Home, a person's week, reports and filter chips say what is true now.
RSpec.describe "Home, person week and reports read right", type: :request do
  let(:today) { Date.new(2027, 7, 8) } # Thursday
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  around { |example| travel_to(today.in_time_zone.change(hour: 11)) { example.run } }

  it "drops leave that already ended this week from Home (VS-24)" do
    sick = create(:leave_type, name: "Sick leave", code: "SL")
    create(:leave_request, user: create(:user, name: "Ravi"), leave_type: sick, start_date: today - 3, end_date: today - 2, status: "approved")
    sign_in meera
    get "/hr/"
    expect(response.body[%r{On leave this week</h2>.*?</section>}m]).not_to include("Ravi")
    expect(response.body.scan('href="/hr/team">Team board').size).to eq(1)
  end

  it "lists a pending work-from-home request with my other requests (NV-3)" do
    HrLite::WfhRequest.create!(user_id: meera.id, start_date: today + 1, end_date: today + 1, reason: "Plumber")
    sign_in meera
    get "/hr/"
    expect(response.body[%r{My requests</h2>.*?</section>}m]).to include("Work from home", "Fri 9 Jul")
  end

  it "marks a day with a pending fix and does not call today absent (VS-6)" do
    create(:employee_profile, user: meera)
    HrLite::RegularizationRequest.create!(user_id: meera.id, date: today - 1, reason: "Forgot",
                                          check_in_at: (today - 1).in_time_zone.change(hour: 9))
    sign_in hr
    get "/hr/admin/attendances/#{meera.id}/summary"
    expect(response.body).to include("Fix pending", "Not in yet")
  end

  it "shows report money, dates and states the way the app does (VS-20)" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    HrLite::Expense.create!(user_id: meera.id, category: category, amount: 2450, spent_on: today, description: "Cab")
    sign_in user_with_roles(HrLite::Role::FINANCE, name: "Farid")
    get "/hr/admin/reports/expenses", params: { month: today.strftime("%Y-%m") }
    expect(response.body).to include("₹2,450.00", "08 Jul 2027", "Draft", "‹ Jun 2027")
  end

  it "marks the chosen filter for assistive tech, not by colour alone (IN-7)" do
    sign_in user_with_roles(HrLite::Role::FINANCE, name: "Farid")
    get "/hr/admin/expenses", params: { status: "approved" }
    expect(response.body).to include('class="hrl-btn" aria-current=true')
  end
end
