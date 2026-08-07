require "rails_helper"

RSpec.describe "Employee lifecycle", type: :request do
  let(:leader) { create(:user, name: "Khushboo", email: "lead@example.com", admin: true) }

  before do
    HrLite.config.leadership_emails = [ leader.email ]
    sign_in leader
  end

  describe "onboarding" do
    it "leaves no login behind when the profile is rejected" do
      # The dummy User has no password column; the real host hook creates a
      # Devise login here. What matters is that it commits before the profile.
      HrLite.config.onboard_user = ->(name:, email:, password:) {
        User.create!(name: name, email: email)
      }

      expect {
        post "/hr/admin/employees", params: {
          employee_profile: {
            new_user_name: "Asha", new_user_email: "asha@example.com",
            date_of_joining: Date.current, tax_regime: "new",
            pan_number: "not-a-pan" # fails the format validation
          }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find_by(email: "asha@example.com")).to be_nil
    end
  end

  describe "the reporting line" do
    let(:boss) { create(:user, name: "Ketan") }
    let!(:boss_profile) { create(:employee_profile, user: boss) }
    let(:profile) do
      # Assign while the manager is still active, then offboard them — the
      # order a real exit happens in.
      p = create(:employee_profile, manager_id: boss.id)
      boss_profile.update!(date_of_exit: Date.current - 1)
      p
    end

    # The select was built from active employees only, so an exited manager
    # had no matching option and the browser posted the blank one.
    it "keeps an exited manager selectable so an unrelated edit does not wipe it" do
      get "/hr/admin/employees/#{profile.id}/edit"

      expect(response.body).to include(%(<option selected="selected" value="#{boss.id}">Ketan</option>))
    end
  end

  describe "offboarding" do
    let(:profile) { create(:employee_profile, date_of_exit: Date.current + 30) }

    # Accepting a resignation stamps an exit date, which used to hide this
    # card — removing the only control that revokes sign-in.
    it "still offers the revoke control once an exit date is stamped" do
      get "/hr/admin/employees/#{profile.id}"

      expect(response.body).to include("Revoke access")
    end

    it "does not 500 on an unparseable exit date" do
      post "/hr/admin/employees/#{profile.id}/offboard", params: { date_of_exit: "not-a-date" }

      expect(response).to have_http_status(:found)
    end
  end

  describe "promotions" do
    let(:user) { create(:user, name: "Meera") }
    let!(:profile) { create(:employee_profile, user: user, designation: "Executive") }

    it "does not let a backdated change overwrite the current designation" do
      HrLite::DesignationChange.create!(user: user, to_designation: "Senior Executive",
                                        effective_date: Date.current)
      expect(profile.reload.designation).to eq("Senior Executive")

      HrLite::DesignationChange.create!(user: user, to_designation: "Executive",
                                        effective_date: Date.current - 365)

      expect(profile.reload.designation).to eq("Senior Executive")
    end
  end

  describe "accepting a resignation for someone with no profile" do
    let(:user) { create(:user, name: "Rahul") }

    it "says so instead of claiming an exit date was recorded" do
      resignation = HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 30)

      post "/hr/admin/resignations/#{resignation.id}/accept"

      expect(resignation.reload).to be_accepted
      expect(flash[:notice]).to include("no exit date was recorded")
    end
  end
end
