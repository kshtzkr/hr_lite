require "rails_helper"

RSpec.describe HrLite::Seeds do
  it "seeds default leave types and fixed national holidays idempotently" do
    first = described_class.run!
    expect(HrLite::LeaveType.pluck(:code)).to contain_exactly("CL", "SL", "EL", "LWP", "CO")
    expect(HrLite::Holiday.count).to eq(3)
    expect(first.length).to eq(8)

    expect { described_class.run! }.not_to change { [ HrLite::LeaveType.count, HrLite::Holiday.count ] }
    expect(described_class.run!).to eq([])
  end

  it "never overwrites operator edits" do
    described_class.run!
    HrLite::LeaveType.find_by(code: "CL").update!(annual_quota: 20)
    described_class.run!
    expect(HrLite::LeaveType.find_by(code: "CL").annual_quota).to eq(20)
  end

  it "keeps LWP unlimited-unpaid" do
    described_class.run!
    lwp = HrLite::LeaveType.find_by(code: "LWP")
    expect(lwp.unlimited?).to be(true)
    expect(lwp.paid).to be(false)
  end

  it "flags CO on fresh installs and NEVER re-flags after an operator disables it" do
    described_class.run!
    expect(HrLite::LeaveType.comp_off_type.code).to eq("CO")

    # Operator turns comp-off OFF; the every-deploy seed must respect that.
    HrLite::LeaveType.find_by(code: "CO").update!(comp_off: false)
    expect(described_class.run!).to eq([])
    expect(HrLite::LeaveType.comp_off_type).to be_nil
  end

  it "upgrades pre-0.3.0 installs via the explicit one-shot helper" do
    described_class.run!
    HrLite::LeaveType.find_by(code: "CO").update!(comp_off: false)
    expect(described_class.seed_comp_off_flag!).to eq([ "comp_off flag on CO" ])
    expect(HrLite::LeaveType.comp_off_type.code).to eq("CO")

    other = HrLite::LeaveType.find_by(code: "CL")
    HrLite::LeaveType.find_by(code: "CO").update!(comp_off: false)
    other.update!(comp_off: true)
    expect(described_class.seed_comp_off_flag!).to eq([])
    expect(HrLite::LeaveType.comp_off_type).to eq(other)
  end

  it "does nothing for installs that never had a CO type" do
    described_class.run!
    type = HrLite::LeaveType.find_by(code: "CO")
    type.leave_balances.delete_all
    type.destroy!
    expect(described_class.seed_comp_off_flag!).to eq([])
  end
end
