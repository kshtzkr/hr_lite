require "rails_helper"

RSpec.describe "My salary on the slips page", type: :request do
  let(:user) { create(:user) }
  let(:lines) { { pf_applicable: true, esi_applicable: false, pt_state: "none" } }

  before { travel_to Date.new(2026, 10, 15) }

  it "shows the employee's own current, upcoming and earlier structures" do
    create(:salary_structure, lines.merge(user: user, effective_from: Date.new(2026, 4, 1),
                                          basic: 17_500, hra: 7000, special_allowance: 8700))
    create(:salary_structure, lines.merge(user: user, effective_from: Date.new(2026, 11, 1)))
    create(:salary_structure, user: user, effective_from: Date.new(2025, 4, 1), basic: 10_000, hra: 4000,
                              special_allowance: 5000, pf_applicable: false, esi_applicable: false)
    create(:salary_structure, user: create(:user), basic: 99_999)
    sign_in user

    get "/hr/salary_slips"

    expect(response.body).to include("Current salary from 01 Apr 2026")
      .and include("₹4,20,000.00").and include("₹33,200.00").and include("₹31,400.00")
      .and include("New salary from 01 Nov 2026")
      .and include("From 01 Apr 2025 — ₹2,28,000.00 a year CTC")
    expect(response.body).not_to include("99,999")
  end

  it "says so when HR has not set a structure, and still lists slips" do
    slip = create(:salary_slip, user: user, payroll_run: create(:payroll_run, period_month: Date.new(2026, 8, 1)))
    slip.payroll_run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    sign_in user

    get "/hr/salary_slips"

    expect(response.body).to include("Your salary structure hasn't been set up yet.").and include("August 2026")
  end
end
