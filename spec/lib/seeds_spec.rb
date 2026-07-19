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
end
