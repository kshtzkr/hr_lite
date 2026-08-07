require "rails_helper"

RSpec.describe "Phone navigation and the boards", type: :request do
  let(:leader) { create(:user, name: "Khushboo", email: "lead@example.com", admin: true) }

  before { HrLite.config.leadership_emails = [ leader.email ] }

  # The left rail is display:none below 768px and the tab bar holds five
  # items, so everything else was unreachable on the surface this is
  # installed on as a PWA.
  describe "the More sheet" do
    it "carries the nav items the tab bar cannot hold" do
      sign_in create(:user)
      get "/hr/"

      expect(response.body).to include("hrl-tabbar__more")
      expect(response.body).to include("/hr/org").and include("/hr/salary_slips").and include("/hr/career")
    end

    it "carries the admin and leadership groups for those entitled to them" do
      sign_in leader
      get "/hr/"

      expect(response.body).to include("/hr/admin/overview").and include("/hr/admin/employees")
    end

    it "offers no admin group to an ordinary employee" do
      sign_in create(:user)
      get "/hr/"

      expect(response.body).not_to include("/hr/admin/overview")
    end
  end

  describe "the overview board" do
    it "counts comp-off and regularization as pending work" do
      employee = create(:user, name: "Meera")
      create(:comp_off_request, user: employee)
      create(:regularization_request, user: employee)

      sign_in leader
      get "/hr/admin/overview"

      expect(response.body).not_to include("All present and accounted for")
      expect(response.body).to include("comp-off for").and include("attendance fix for")
    end
  end

  describe "confirmation prompts" do
    it "loads the script that reads data-turbo-confirm" do
      sign_in create(:user)
      get "/hr/"

      # Without this the engine's destructive buttons fired on first click:
      # nothing shipped that read the attribute.
      expect(response.body).to match(%r{hr_lite/confirm.*\.js})
    end
  end
end
