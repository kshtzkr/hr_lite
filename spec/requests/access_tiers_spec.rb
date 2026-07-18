require "rails_helper"

RSpec.describe "Access tiers", type: :request do
  let(:employee) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:leader) { create(:user, email: "lead@x.test") }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  describe "employee surface" do
    it "requires authentication" do
      get "/hr/"
      expect(response).to have_http_status(:unauthorized)
    end

    it "welcomes any signed-in user" do
      sign_in employee
      get "/hr/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hello,")
    end
  end

  describe "leadership surface (audit trail)" do
    it "denies employees" do
      sign_in employee
      get "/hr/admin/audit_logs"
      expect(response).to redirect_to("/hr/")
    end

    it "denies admins who are not leadership" do
      sign_in admin
      get "/hr/admin/audit_logs"
      expect(response).to redirect_to("/hr/")
    end

    it "admits leadership (even non-admin)" do
      sign_in leader
      get "/hr/admin/audit_logs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Audit trail")
    end
  end

  describe "nav visibility" do
    it "hides governing links from employees, shows them to leadership" do
      sign_in employee
      get "/hr/"
      expect(response.body).not_to include("Audit")

      sign_in leader
      get "/hr/"
      expect(response.body).to include("Audit")
    end
  end

  describe "audit trail contents" do
    it "lists logged changes" do
      HrLite::AuditLog.create!(actor: admin, action: "update", subject_type: "HrLite::Probe",
                               subject_id: 1, audited_changes: { "quota" => [ 12, 15 ] })
      sign_in leader
      get "/hr/admin/audit_logs"
      expect(response.body).to include("Quota").and include("12").and include("15")
    end
  end
end
