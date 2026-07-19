require "rails_helper"

RSpec.describe "Leadership settings", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:leader) { create(:user, email: "lead@x.test") }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  describe "gating: policy screens are leadership-only" do
    %w[/hr/admin/leave_types /hr/admin/office_locations /hr/admin/holidays /hr/admin/setting/edit].each do |path|
      it "blocks admins from #{path}" do
        sign_in admin
        get path
        expect(response).to redirect_to("/hr/")
      end

      it "admits leadership to #{path}" do
        sign_in leader
        get path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "leave types CRUD" do
    before { sign_in leader }

    it "creates, updates, audits and emails leadership on policy change" do
      expect {
        post "/hr/admin/leave_types", params: {
          leave_type: { name: "Casual", code: "CL", color: "#0ea5e9", paid: "1",
                        annual_quota: 12, accrual: "monthly", carry_forward_cap: 0, active: "1", position: 1 }
        }
      }.to change(HrLite::LeaveType, :count).by(1)
        .and change(HrLite::AuditLog, :count).by(1)
        .and have_enqueued_mail(HrLite::EventMailer, :leadership).once

      leave_type = HrLite::LeaveType.last
      patch "/hr/admin/leave_types/#{leave_type.id}", params: { leave_type: { annual_quota: 15 } }
      log = HrLite::AuditLog.order(:id).last
      expect(log.audited_changes["annual_quota"]).to eq([ "12.0", "15.0" ])
    end

    it "re-renders invalid forms" do
      post "/hr/admin/leave_types", params: { leave_type: { name: "", code: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses to destroy a type with history, allows without" do
      used = create(:leave_type)
      workday = Date.current.next_occurring(:tuesday)
      create(:leave_request, leave_type: used, start_date: workday, end_date: workday)
      delete "/hr/admin/leave_types/#{used.id}"
      expect(HrLite::LeaveType.exists?(used.id)).to be(true)
      expect(flash[:alert]).to include("deactivate")

      fresh = create(:leave_type)
      delete "/hr/admin/leave_types/#{fresh.id}"
      expect(HrLite::LeaveType.exists?(fresh.id)).to be(false)
    end
  end

  describe "office locations CRUD" do
    before { sign_in leader }

    it "creates, updates and destroys" do
      post "/hr/admin/office_locations", params: {
        office_location: { name: "HQ", lat: 28.6315, lng: 77.2167, radius_m: 250, active: "1" }
      }
      office = HrLite::OfficeLocation.last
      expect(office.name).to eq("HQ")

      patch "/hr/admin/office_locations/#{office.id}", params: { office_location: { radius_m: 400 } }
      expect(office.reload.radius_m).to eq(400)

      delete "/hr/admin/office_locations/#{office.id}"
      expect(HrLite::OfficeLocation.exists?(office.id)).to be(false)
    end

    it "re-renders invalid forms" do
      post "/hr/admin/office_locations", params: { office_location: { name: "", lat: 999, lng: 0 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "holidays management" do
    before { sign_in leader }

    it "adds a single holiday" do
      post "/hr/admin/holidays", params: { holiday: { date: "2027-03-04", name: "Holi", optional: "0" } }
      expect(HrLite::Holiday.find_by(name: "Holi").date).to eq(Date.new(2027, 3, 4))
    end

    it "bulk-pastes with per-line problems and duplicate skipping" do
      create(:holiday, date: Date.new(2027, 11, 9), name: "Existing")

      post "/hr/admin/holidays/bulk_create", params: { lines: <<~LINES }
        2027-11-09, Diwali
        2027-12-25, Christmas, optional
        garbage line
        2027-01-14, Pongal
      LINES

      expect(HrLite::Holiday.where(name: %w[Christmas Pongal]).count).to eq(2)
      expect(HrLite::Holiday.find_by(name: "Christmas").optional).to be(true)
      expect(HrLite::Holiday.where(name: "Diwali")).to be_empty # duplicate date skipped
      expect(flash[:alert]).to include("Line 3")
    end

    it "updates and destroys" do
      holiday = create(:holiday, name: "Temp", date: Date.new(2027, 5, 1))
      patch "/hr/admin/holidays/#{holiday.id}", params: { holiday: { name: "May Day" } }
      expect(holiday.reload.name).to eq("May Day")

      delete "/hr/admin/holidays/#{holiday.id}"
      expect(HrLite::Holiday.exists?(holiday.id)).to be(false)
    end

    it "surfaces validation problems as alerts" do
      post "/hr/admin/holidays", params: { holiday: { date: "", name: "" } }
      expect(flash[:alert]).to be_present
    end
  end

  describe "weekend policy" do
    before { sign_in leader }

    it "updates the singleton and audits" do
      expect {
        patch "/hr/admin/setting", params: { setting: { weekend_policy: "second_fourth_sat_sun" } }
      }.to change { HrLite::Setting.instance.weekend_policy }.to("second_fourth_sat_sun")

      expect(HrLite::AuditLog.order(:id).last.audited_changes).to include("weekend_policy")
    end

    it "rejects unknown policies" do
      patch "/hr/admin/setting", params: { setting: { weekend_policy: "no_work_ever" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
