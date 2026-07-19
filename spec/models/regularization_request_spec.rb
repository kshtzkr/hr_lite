require "rails_helper"

RSpec.describe HrLite::RegularizationRequest do
  let(:user) { create(:user, name: "Dev") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let(:tuesday) { Date.new(2027, 7, 6) }

  before { travel_to(Date.new(2027, 7, 8)) }
  after { travel_back }

  def build_request(**attrs)
    build(:regularization_request, {
      user: user, date: tuesday,
      check_in_at: tuesday.in_time_zone.change(hour: 10),
      check_out_at: tuesday.in_time_zone.change(hour: 19)
    }.merge(attrs))
  end

  describe "create validations" do
    it "accepts a full-day proposal and labels the times" do
      request = build_request
      expect(request).to be_valid
      expect(request.times_label).to eq("10:00 – 19:00")
    end

    it "accepts a checkout-only proposal (check-in was genuine)" do
      expect(build_request(check_in_at: nil)).to be_valid
    end

    it "rejects future dates" do
      request = build_request(date: Date.new(2027, 7, 12),
                              check_in_at: Date.new(2027, 7, 12).in_time_zone.change(hour: 10),
                              check_out_at: nil)
      expect(request).not_to be_valid
      expect(request.errors[:date].join).to include("future")
    end

    it "demands at least one time" do
      request = build_request(check_in_at: nil, check_out_at: nil)
      expect(request).not_to be_valid
      expect(request.errors[:base].join).to include("check-in time")
    end

    it "pins the times to the ticket's date" do
      request = build_request(check_out_at: (tuesday + 1).in_time_zone.change(hour: 2))
      expect(request).not_to be_valid
      expect(request.errors[:check_out_at].join).to include("must be on")
    end

    it "rejects checkout before check-in" do
      request = build_request(check_out_at: tuesday.in_time_zone.change(hour: 9))
      expect(request).not_to be_valid
      expect(request.errors[:check_out_at].join).to include("after check-in")
    end

    it "allows only one pending ticket per date" do
      build_request.save!
      dup = build_request
      expect(dup).not_to be_valid
      expect(dup.errors[:date].join).to include("pending")
    end

    it "requires a reason" do
      expect(build_request(reason: " ")).not_to be_valid
    end
  end

  describe "#approve!" do
    it "creates the day's record with the proposed times and the full trail" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      request = build_request
      request.save!

      expect(request.approve!(actor: admin)).to be(true)
      record = HrLite::AttendanceRecord.find_by!(user_id: user.id, date: tuesday)
      expect(record.check_in_at).to eq(request.check_in_at)
      expect(record.check_out_at).to eq(request.check_out_at)
      expect(record.status).to eq("present")
      expect(record.regularized_by_id).to eq(admin.id)
      expect(record.regularized_at).to be_present
      expect(record.regularization_note).to include("Ticket ##{request.id}")
      expect(bells.map { |b| b[:kind] }).to include("regularization.approved")
    end

    it "overwrites only the proposed time on an existing punch" do
      genuine_in = tuesday.in_time_zone.change(hour: 9, min: 12)
      create(:attendance_record, user: user, date: tuesday, check_in_at: genuine_in)
      request = build_request(check_in_at: nil)
      request.save!

      request.approve!(actor: admin)
      record = HrLite::AttendanceRecord.find_by!(user_id: user.id, date: tuesday)
      expect(record.check_in_at).to eq(genuine_in)
      expect(record.check_out_at).to eq(request.check_out_at)
    end

    it "refuses to decide twice" do
      request = build_request
      request.save!
      request.approve!(actor: admin)
      expect { request.approve!(actor: admin) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#approve! merge safety" do
    it "refuses a checkout-only ticket when the day has no check-in at all" do
      request = build_request(check_in_at: nil)
      request.save!
      expect { request.approve!(actor: admin) }
        .to raise_error(HrLite::RegularizationRequest::InvalidMerge, /no check-in/)
      expect(request.reload).to be_pending
      expect(HrLite::AttendanceRecord.exists?(user_id: user.id, date: tuesday)).to be(false)
    end

    it "refuses a merge that would put checkout before the existing genuine check-in" do
      create(:attendance_record, user: user, date: tuesday,
             check_in_at: tuesday.in_time_zone.change(hour: 11))
      request = build_request(check_in_at: nil,
                              check_out_at: tuesday.in_time_zone.change(hour: 10, min: 30))
      request.save!

      expect { request.approve!(actor: admin) }
        .to raise_error(HrLite::RegularizationRequest::InvalidMerge, /after check-in/)
      expect(request.reload).to be_pending
    end

    it "keeps the GPS flag (and note) on a regularized record and writes an audit row" do
      record = create(:attendance_record, :flagged, user: user, date: tuesday,
                      check_in_at: tuesday.in_time_zone.change(hour: 9))
      request = build_request(check_in_at: nil)
      request.save!

      expect { request.approve!(actor: admin) }.to change(HrLite::AuditLog, :count).by(1)
      record.reload
      expect(record.flagged).to be(true)
      expect(record.flag_note).to be_present
      log = HrLite::AuditLog.order(:id).last
      expect(log.action).to eq("regularize")
      expect(log.audited_changes["ticket"]).to eq(request.id)
    end
  end

  it "cannot be raised for a day covered by approved full-day leave" do
    type = create(:leave_type, annual_quota: 12)
    leave = create(:leave_request, user: user, leave_type: type, start_date: tuesday, end_date: tuesday)
    leave.update!(status: "approved")

    request = build_request
    expect(request).not_to be_valid
    expect(request.errors[:date].join).to include("approved leave")
  end

  describe "#reject! and #cancel!" do
    it "rejects with a note, leaving attendance untouched" do
      request = build_request
      request.save!
      request.reject!(actor: admin, note: "You were on leave that day")
      expect(request.reload).to be_rejected
      expect(HrLite::AttendanceRecord.exists?(user_id: user.id, date: tuesday)).to be(false)
    end

    it "cancels a pending ticket and bells admins" do
      admin
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      request = build_request
      request.save!
      request.cancel!(actor: user)
      expect(request.reload).to be_cancelled
      expect(bells.map { |b| b[:kind] }).to include("regularization.cancelled")
    end
  end

  it "bells admins on create with the proposed times" do
    admin
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }
    build_request.save!
    requested = bells.select { |b| b[:kind] == "regularization.requested" }
    expect(requested.first[:title]).to include("10:00 – 19:00")
  end

  it "shows the current punch to the approver" do
    record = create(:attendance_record, user: user, date: tuesday,
                    check_in_at: tuesday.in_time_zone.change(hour: 9))
    request = build_request(check_in_at: nil)
    expect(request.punch).to eq(record)
  end
end
