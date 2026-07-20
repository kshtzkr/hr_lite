require "rails_helper"

RSpec.describe HrLite::EmployeeProfile, "system-assigned employee codes" do
  it "assigns prefix + zero-padded sequence automatically" do
    first = described_class.create!(user_id: create(:user).id, date_of_joining: Date.new(2026, 1, 5))
    second = described_class.create!(user_id: create(:user).id, date_of_joining: Date.new(2026, 2, 5))
    expect(first.employee_code).to eq("EMP001")
    expect(second.employee_code).to eq("EMP002")
  end

  it "continues after the highest existing number, ignoring foreign prefixes" do
    create(:employee_profile, employee_code: "EMP041")
    create(:employee_profile, employee_code: "OLD999")
    fresh = described_class.create!(user_id: create(:user).id, date_of_joining: Date.current)
    expect(fresh.employee_code).to eq("EMP042")
  end

  it "restarts a fresh sequence when leadership changes the prefix" do
    create(:employee_profile, employee_code: "EMP007")
    HrLite::Setting.instance.update!(employee_code_prefix: "ESC")
    fresh = described_class.create!(user_id: create(:user).id, date_of_joining: Date.current)
    expect(fresh.employee_code).to eq("ESC001")
  end

  it "never overwrites an explicitly-set code (seeds, imports)" do
    kept = create(:employee_profile, employee_code: "IMPORTED9")
    expect(kept.employee_code).to eq("IMPORTED9")
  end

  it "validates the prefix on Settings" do
    setting = HrLite::Setting.instance
    expect(setting.update(employee_code_prefix: "123")).to be(false)
    expect(setting.update(employee_code_prefix: "")).to be(false)
    expect(setting.update(employee_code_prefix: "ESC")).to be(true)
  end
end
