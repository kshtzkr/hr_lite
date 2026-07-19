require "rails_helper"

RSpec.describe "Onboarding and offboarding", type: :request do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:bells) { [] }

  before do
    HrLite.config.leadership_emails = [ "lead@x.test" ]
    HrLite.config.notify = ->(**kw) { bells << kw }
    sign_in leader
  end

  describe "onboarding a brand-new person" do
    it "creates the login via the hook plus the profile, and welcomes them" do
      expect {
        post "/hr/admin/employees", params: { employee_profile: {
          new_user_name: "Naya Joinee", new_user_email: "naya@x.test", new_user_password: "start-123!",
          employee_code: "EMP100", designation: "Ops", date_of_joining: Date.current.to_s, tax_regime: "new"
        } }
      }.to change(User, :count).by(1)
        .and change(HrLite::EmployeeProfile, :count).by(1)

      user = User.find_by(email: "naya@x.test")
      expect(user.name).to eq("Naya Joinee")
      expect(HrLite::EmployeeProfile.last.user_id).to eq(user.id)
      expect(bells.map { |b| b[:kind] }).to include("employee.onboarded")
    end

    it "surfaces login-creation failures without a profile" do
      create(:user, email: "dupe@x.test")
      expect {
        post "/hr/admin/employees", params: { employee_profile: {
          new_user_email: "dupe@x.test", new_user_password: "x",
          employee_code: "EMP101", date_of_joining: Date.current.to_s, tax_regime: "new"
        } }
      }.not_to change(HrLite::EmployeeProfile, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Could not create the login")
    end

    it "surfaces validation-style hook failures too" do
      HrLite.config.onboard_user = ->(**) {
        record = User.new
        record.errors.add(:email, "is not allowed by the directory")
        raise ActiveRecord::RecordInvalid, record
      }
      post "/hr/admin/employees", params: { employee_profile: {
        new_user_email: "blocked@x.test", new_user_password: "x",
        employee_code: "EMP103", date_of_joining: Date.current.to_s, tax_regime: "new"
      } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("not allowed by the directory")
    end

    it "sets passwords through the default hook when the user model supports them" do
      password_klass = Class.new(User) do
        attr_accessor :password, :password_confirmation
        def self.name = "PasswordUser"
      end
      stub_const("PasswordUser", password_klass)
      HrLite.config.user_class = "PasswordUser"

      user = HrLite.config.onboard_user.call(name: "P W", email: "pw@x.test", password: "secret-1")
      expect(user).to be_persisted
      expect(user.password).to eq("secret-1")
      expect(user.password_confirmation).to eq("secret-1")
    end

    it "sends a set-your-password invite when the host provides invite_url_for" do
      HrLite.config.invite_url_for = ->(user) { "https://hr.x.test/set-password?token=abc-#{user.id}" }
      captured = nil
      allow(HrLite::EventMailer).to receive(:event) do |**kw|
        captured = kw
        instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      end

      post "/hr/admin/employees", params: { employee_profile: {
        new_user_name: "Invited One", new_user_email: "invited@x.test", new_user_password: "",
        employee_code: "EMP104", date_of_joining: Date.current.to_s, tax_regime: "new"
      } }

      user = User.find_by(email: "invited@x.test")
      expect(user).to be_present
      expect(captured[:link_url]).to eq("https://hr.x.test/set-password?token=abc-#{user.id}")
      expect(captured[:body]).to include("Set your password")
    end

    it "honours a host-overridden onboard_user hook" do
      called = nil
      HrLite.config.onboard_user = ->(name:, email:, password:) {
        called = email
        create(:user, email: email, name: name)
      }
      post "/hr/admin/employees", params: { employee_profile: {
        new_user_name: "Via Hook", new_user_email: "hook@x.test", new_user_password: "pw",
        employee_code: "EMP102", date_of_joining: Date.current.to_s, tax_regime: "new"
      } }
      expect(called).to eq("hook@x.test")
    end
  end

  describe "offboarding" do
    it "stamps the exit date and calls the host hook" do
      revoked = nil
      HrLite.config.offboard_user = ->(user) { revoked = user.email }
      profile = create(:employee_profile)

      post "/hr/admin/employees/#{profile.id}/offboard", params: { date_of_exit: (Date.current + 7).to_s }

      expect(profile.reload.date_of_exit).to eq(Date.current + 7)
      expect(revoked).to eq(profile.user.email)
    end

    it "survives a failing offboard hook (exit date still recorded)" do
      HrLite.config.offboard_user = ->(_user) { raise "ldap down" }
      profile = create(:employee_profile)
      post "/hr/admin/employees/#{profile.id}/offboard"
      expect(profile.reload.date_of_exit).to eq(Date.current)
    end
  end
end
