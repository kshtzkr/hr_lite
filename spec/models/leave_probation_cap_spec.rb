require "rails_helper"

RSpec.describe "Probation leave cap" do
  let(:user) { create(:user) }
  let(:type) { create(:leave_type, annual_quota: 12) }
  let(:profile) { HrLite::EmployeeProfile.find_by(user_id: user.id) }

  before do
    HrLite.config.probation_months = 6
    create(:employee_profile, user: user, date_of_joining: Date.new(2027, 1, 4))
    travel_to(Date.new(2027, 2, 1))
  end

  after { travel_back }

  def apply(on)
    build(:leave_request, user: user, leave_type: type, start_date: on, end_date: on)
  end

  it "tags a new hire until joining + 6 months and allows one day a month" do
    expect(profile.probation_until).to eq(Date.new(2027, 7, 3))
    apply(Date.new(2027, 2, 3)).save!

    second = apply(Date.new(2027, 2, 10))
    expect(second).not_to be_valid
    expect(second.errors[:base]).to include("During probation only 1 day of leave a month is allowed")
    expect(apply(Date.new(2027, 3, 3))).to be_valid
  end

  it "lets HR record leave past the cap" do
    apply(Date.new(2027, 2, 3)).save!
    recorded = apply(Date.new(2027, 2, 10))
    recorded.created_by_id = create(:user, :admin).id
    expect(recorded).to be_valid
  end

  it "drops the tag and the cap when the admin clears the date" do
    apply(Date.new(2027, 2, 3)).save!
    profile.update!(probation_until: nil)

    expect(profile.on_probation?).to be(false)
    expect(apply(Date.new(2027, 2, 10))).to be_valid
  end

  it "ends on its own after the date" do
    travel_to(Date.new(2027, 7, 5)) { expect(profile.on_probation?).to be(false) }
  end
end
