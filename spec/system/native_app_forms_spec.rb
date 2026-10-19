require "rails_helper"

# Native pages turn every Turbo visit into a full reload (see the layout). A
# form's answer must survive that: the flash after a save, the errors and the
# typed values after a refusal.
RSpec.describe "Forms in the native app", type: :system do
  let(:user) { create(:employee_profile).user }
  let(:day) { Date.current.next_occurring(:tuesday) }

  before do
    create(:leave_type, name: "Casual")
    driven_by :selenium, using: :headless_chrome do |options|
      options.add_argument("--user-agent=Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS;")
    end
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  def apply_for_leave
    visit "/hr/leave_requests/new"
    choose "Casual", allow_label_click: true
    fill_in "From", with: day
    click_on "Send for approval"
  end

  it "confirms a save, and keeps the errors and the typed date on a refusal" do
    apply_for_leave
    expect(page).to have_css(".hrl-flash--ok", text: "Leave request submitted.")

    apply_for_leave # the same day again overlaps
    expect(page).to have_css(".hrl-errors", text: "overlaps")
    expect(page).to have_field("From", with: day.iso8601)
  end
end
