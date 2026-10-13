require "rails_helper"

RSpec.describe "work_analytics.view" do
  it "is seeded for HR, Leadership and Super Admin, never Manager or Employee" do
    defs = HrLite::RoleSeeds.definitions
    expect(defs.select { |_, d| d[:grants]["work_analytics.view"] == "all" }.keys)
      .to contain_exactly(HrLite::Role::HR, HrLite::Role::LEADERSHIP, HrLite::Role::SUPER_ADMIN)
    expect(defs[HrLite::Role::MANAGER][:grants]).not_to have_key("work_analytics.view")
  end
end
