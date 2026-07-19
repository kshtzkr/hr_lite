require "rails_helper"

RSpec.describe "Resignations", type: :request do
  let(:employee) { create(:user, name: "Asha") }
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:bells) { [] }

  before do
    HrLite.config.leadership_emails = [ "lead@x.test" ]
    HrLite.config.notify = ->(**kw) { bells << kw }
  end

  describe "employee flow" do
    before { sign_in employee }

    it "submits a resignation, notifies leadership, blocks duplicates" do
      expect {
        post "/hr/resignation", params: { resignation: {
          proposed_last_day: Date.current + 30, reason: "Moving cities"
        } }
      }.to change(HrLite::Resignation, :count).by(1)
        .and have_enqueued_mail(HrLite::EventMailer, :leadership).once

      follow_redirect!
      expect(response.body).to include("Pending").and include("Moving cities")

      post "/hr/resignation", params: { resignation: { proposed_last_day: Date.current + 40 } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("already have a pending resignation")
    end

    it "rejects past last days" do
      post "/hr/resignation", params: { resignation: { proposed_last_day: Date.current - 1 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "politely refuses a withdraw with nothing pending" do
      post "/hr/resignation/withdraw"
      expect(flash[:alert]).to eq("Nothing pending to withdraw.")
    end

    it "withdraws while pending and notifies admins" do
      create(:user, :admin)
      post "/hr/resignation", params: { resignation: { proposed_last_day: Date.current + 30 } }
      post "/hr/resignation/withdraw"
      expect(HrLite::Resignation.last).to be_withdrawn
      expect(bells.map { |b| b[:kind] }).to include("resignation.withdrawn")
    end
  end

  describe "leadership acceptance" do
    it "accepts with a confirmed last day, stamping the profile exit date" do
      profile = create(:employee_profile, user: employee)
      sign_in employee
      post "/hr/resignation", params: { resignation: { proposed_last_day: Date.current + 30 } }
      resignation = HrLite::Resignation.last

      sign_in leader
      post "/hr/admin/resignations/#{resignation.id}/accept",
           params: { last_day: (Date.current + 45).to_s, note: "Serve full notice" }

      expect(resignation.reload).to be_accepted
      expect(resignation.decided_by_id).to eq(leader.id)
      expect(resignation.proposed_last_day).to eq(Date.current + 45)
      expect(profile.reload.date_of_exit).to eq(Date.current + 45)
      expect(bells.map { |b| b[:kind] }).to include("resignation.accepted")
    end

    it "is leadership-only and pending-only" do
      sign_in employee
      post "/hr/resignation", params: { resignation: { proposed_last_day: Date.current + 30 } }
      resignation = HrLite::Resignation.last

      sign_in create(:user, :admin)
      post "/hr/admin/resignations/#{resignation.id}/accept"
      expect(response).to redirect_to("/hr/")
      expect(resignation.reload).to be_pending

      sign_in leader
      post "/hr/admin/resignations/#{resignation.id}/accept"
      post "/hr/admin/resignations/#{resignation.id}/accept"
      expect(flash[:alert]).to include("Only pending")
    end
  end
end
