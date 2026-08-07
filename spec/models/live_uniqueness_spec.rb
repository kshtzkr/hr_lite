require "rails_helper"

# The models validate each of these, but a validation is a read-then-write:
# two concurrent requests both see nothing and both insert. These examples
# bypass the validations (insert_all / update_column) to prove the DATABASE
# refuses the duplicate, which is the only thing a race respects.
RSpec.describe "Live-row uniqueness is enforced by the database" do
  let(:user) { create(:user, name: "Meera") }

  it "allows only one pending resignation per person" do
    HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 30)

    expect {
      HrLite::Resignation.insert_all!([ {
        user_id: user.id, proposed_last_day: Date.current + 45, status: "pending",
        created_at: Time.current, updated_at: Time.current
      } ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "still allows a fresh resignation once the previous one is settled" do
    first = HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 30)
    first.update_column(:status, "withdrawn")

    expect {
      HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 60)
    }.to change(HrLite::Resignation, :count).by(1)
  end

  it "allows only one pending regularization per person per day" do
    date = Date.current - 2
    create(:regularization_request, user: user, date: date)

    expect {
      HrLite::RegularizationRequest.insert_all!([ {
        user_id: user.id, date: date, reason: "again", status: "pending",
        created_at: Time.current, updated_at: Time.current
      } ])
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "the comp-off flag" do
    it "allows only one leave type to carry it" do
      create(:leave_type, :comp_off, code: "CO", name: "Comp off")
      other = create(:leave_type, code: "CO2", name: "Comp off 2")

      expect { other.update_column(:comp_off, true) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # Retiring the flagged type hands the flag back — otherwise the resolver
    # (which reads through `active`) finds nothing and every comp-off approval
    # fails, while the index blocks a replacement from taking the flag.
    it "is released when the type is retired, so a replacement can take it" do
      old = create(:leave_type, :comp_off, code: "CO", name: "Comp off")
      old.update!(active: false)

      expect(old.reload.comp_off).to be(false)

      replacement = create(:leave_type, :comp_off, code: "CO2", name: "Comp off 2026-27")
      expect(HrLite::LeaveType.comp_off_type).to eq(replacement)
    end
  end
end
