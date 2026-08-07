require "rails_helper"

RSpec.describe "Presentation and lifecycle edges", type: :request do
  let(:user) { create(:user, name: "Meera") }
  let(:leader) { create(:user, name: "Asha", email: "lead@x.test", admin: true) }

  before { HrLite.config.leadership_emails = [ leader.email ] }

  describe "the career page" do
    # `timeline` orders newest-first, so a promotion recorded for next quarter
    # dated the CURRENT role from a month that has not arrived.
    it "dates the current role from the change actually in force" do
      create(:employee_profile, user: user, date_of_joining: Date.new(2024, 1, 1),
             designation: "Executive")
      HrLite::DesignationChange.create!(user: user, to_designation: "Senior Executive",
                                        effective_date: Date.current - 30)
      HrLite::DesignationChange.create!(user: user, to_designation: "Lead",
                                        effective_date: Date.current + 60)

      sign_in user
      get "/hr/career"

      expect(response.body).to include("since #{(Date.current - 30).strftime('%b %Y')}")
    end
  end

  describe "resigning twice" do
    # Only `pending` used to block a second one, so an agreed exit could be
    # re-filed and accepting the new one would overwrite the date payroll and
    # attendance already clip to.
    it "is refused once a resignation has been accepted" do
      create(:employee_profile, user: user)
      resignation = HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 30)
      resignation.accept!(actor: leader)

      second = HrLite::Resignation.new(user: user, proposed_last_day: Date.current + 90)

      expect(second).not_to be_valid
      expect(second.errors.full_messages.join).to include("already been accepted")
    end

    it "offers no resignation form once one is accepted" do
      create(:employee_profile, user: user)
      HrLite::Resignation.create!(user: user, proposed_last_day: Date.current + 30)
                         .accept!(actor: leader)

      sign_in user
      get "/hr/resignation"

      expect(response.body).not_to include("Submit resignation")
    end
  end

  describe "the org chart's reporting line" do
    # The L-labels are positional, so skipping an exited manager promoted
    # everyone above them and contradicted the tree below.
    it "stops at the first manager who has left" do
      grandboss = create(:user, name: "Ketan")
      boss = create(:user, name: "Sadique")
      create(:employee_profile, user: grandboss)
      boss_profile = create(:employee_profile, user: boss, manager_id: grandboss.id)
      create(:employee_profile, user: user, manager_id: boss.id)
      boss_profile.update_column(:date_of_exit, Date.current - 1)

      sign_in user
      get "/hr/org"

      expect(response.body).not_to include("L1 · Ketan")
    end
  end

  describe "a mid-month joiner's slip" do
    it "names the days outside employment instead of losing them" do
      profile = create(:employee_profile, user: user,
                       date_of_joining: Date.current.prev_month.beginning_of_month + 15)
      structure = create(:salary_structure, user: user, effective_from: Date.new(2024, 1, 1),
                         basic: 30000, hra: nil, special_allowance: nil)
      run = create(:payroll_run)
      attrs = HrLite::SlipBuilder.call(run: run, user: user, structure: structure, profile: profile)

      expect(attrs[:out_of_window_days]).to be_positive
      expect(attrs[:payable_days] + attrs[:lop_days] + attrs[:out_of_window_days])
        .to eq(attrs[:days_in_month])
    end
  end
end
