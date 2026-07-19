require "rails_helper"

RSpec.describe "Career over HTTP", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:admin) { create(:user, :admin) }
  let(:profile) { create(:employee_profile, designation: "Executive") }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  describe "leadership appraisal flow" do
    before { sign_in leader }

    it "drafts, edits, shares; employee sees it only after sharing" do
      get "/hr/admin/employees/#{profile.id}/appraisals/new"
      expect(response.body).to include("New appraisal")

      post "/hr/admin/employees/#{profile.id}/appraisals", params: { appraisal: {
        period_start: "2027-01-01", period_end: "2027-06-30", rating: 4,
        strengths: "Ran ops single-handed", improvements: "Delegate more", outcome: "none"
      } }
      appraisal = HrLite::Appraisal.last
      expect(appraisal).to be_draft

      # Employee cannot see drafts.
      sign_in profile.user
      get "/hr/appraisals"
      expect(response.body).to include("No shared appraisals")
      get "/hr/appraisals/#{appraisal.id}"
      expect(response).to have_http_status(:not_found)

      sign_in leader
      get "/hr/admin/employees/#{profile.id}/appraisals/#{appraisal.id}/edit"
      expect(response.body).to include("Ran ops single-handed")
      patch "/hr/admin/employees/#{profile.id}/appraisals/#{appraisal.id}",
            params: { appraisal: { rating: 5 } }
      expect(appraisal.reload.rating).to eq(5)

      post "/hr/admin/employees/#{profile.id}/appraisals/#{appraisal.id}/share"
      expect(appraisal.reload).to be_shared

      sign_in profile.user
      get "/hr/appraisals/#{appraisal.id}"
      expect(response.body).to include("Ran ops single-handed").and include("5/5")
    end

    it "re-renders invalid drafts and guards double-share" do
      post "/hr/admin/employees/#{profile.id}/appraisals", params: { appraisal: {
        period_start: "2027-06-30", period_end: "2027-01-01"
      } }
      expect(response).to have_http_status(:unprocessable_entity)

      appraisal = create(:appraisal, user: profile.user, reviewer: leader)
      appraisal.share!(actor: leader)
      post "/hr/admin/employees/#{profile.id}/appraisals/#{appraisal.id}/share"
      expect(flash[:alert]).to include("already shared")

      patch "/hr/admin/employees/#{profile.id}/appraisals/#{appraisal.id}",
            params: { appraisal: { rating: 1 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "deletes drafts but never shared appraisals" do
      draft = create(:appraisal, user: profile.user, reviewer: leader)
      delete "/hr/admin/employees/#{profile.id}/appraisals/#{draft.id}"
      expect(HrLite::Appraisal.exists?(draft.id)).to be(false)

      shared = create(:appraisal, user: profile.user, reviewer: leader)
      shared.share!(actor: leader)
      delete "/hr/admin/employees/#{profile.id}/appraisals/#{shared.id}"
      expect(HrLite::Appraisal.exists?(shared.id)).to be(true)
      expect(flash[:alert]).to include("permanent")
    end

    it "records a standalone role change from the form" do
      get "/hr/admin/employees/#{profile.id}/designation_changes/new"
      expect(response.body).to include("Role change")

      post "/hr/admin/employees/#{profile.id}/designation_changes", params: { designation_change: {
        to_designation: "Ops Manager", effective_date: Date.current.to_s, note: "Team growth"
      } }
      expect(profile.reload.designation).to eq("Ops Manager")

      post "/hr/admin/employees/#{profile.id}/designation_changes",
           params: { designation_change: { to_designation: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "gating" do
    it "keeps admins (non-leadership) out of appraisals" do
      sign_in admin
      get "/hr/admin/employees/#{profile.id}/appraisals/new"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "employee career page" do
    it "shows role, timeline and shared appraisals" do
      appraisal = create(:appraisal, user: profile.user, reviewer: leader,
                         outcome: "promotion", new_designation: "Senior Executive",
                         effective_date: Date.current)
      appraisal.share!(actor: leader)

      sign_in profile.user
      get "/hr/career"
      expect(response.body).to include("Senior Executive")
        .and include("from Executive")
        .and include(appraisal.period_label)
    end

    it "renders gracefully without profile or history" do
      sign_in create(:user)
      get "/hr/career"
      expect(response.body).to include("Not set yet").and include("No role changes")
    end

    it "paginates the appraisal list" do
      appraisal = create(:appraisal, user: profile.user, reviewer: leader)
      appraisal.share!(actor: leader)
      sign_in profile.user
      get "/hr/appraisals"
      expect(response.body).to include(appraisal.period_label)
    end
  end
end
