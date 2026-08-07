require "rails_helper"

RSpec.describe "Payroll only runs on a month that has ended" do
  around { |example| travel_to(Date.new(2027, 7, 15)) { example.run } }

  it "accepts a month that has already ended" do
    expect(build(:payroll_run, period_month: Date.new(2027, 6, 1))).to be_valid
  end

  # Days that have not happened score as `upcoming`, which the slip folds into
  # payable — so a run for the current month pays for days nobody has worked,
  # and finalizing makes those slips immutable.
  it "refuses the current month" do
    run = build(:payroll_run, period_month: Date.new(2027, 7, 1))

    expect(run).not_to be_valid
    expect(run.errors[:period_month]).to include("must be a month that has already ended")
  end

  it "refuses a future month" do
    expect(build(:payroll_run, period_month: Date.new(2027, 9, 1))).not_to be_valid
  end

  # The guard is create-only: a run made legitimately last month must stay
  # transitionable for as long as it exists.
  it "lets an existing run keep transitioning" do
    run = create(:payroll_run, period_month: Date.new(2027, 6, 1))

    expect(run.update(notes: "checked")).to be(true)
  end

  it "never pays for days that have not happened" do
    profile = create(:employee_profile, date_of_joining: Date.new(2024, 1, 1))
    structure = create(:salary_structure, user: profile.user, basic: 30000, hra: nil,
                                          special_allowance: nil)
    run = create(:payroll_run, period_month: Date.new(2027, 6, 1))

    attrs = HrLite::SlipBuilder.call(run: run, user: profile.user,
                                     structure: structure, profile: profile)

    expect(attrs[:payable_days]).to be <= 30
    expect(attrs[:payable_days] + attrs[:lop_days]).to eq(30)
  end
end
