require "rails_helper"

RSpec.describe HrLite::CompOffRequest do
  let(:user) { create(:user, name: "Meera") }
  let(:admin) { create(:user, name: "Rohan", admin: true) }
  let!(:co_type) { create(:leave_type, :comp_off, code: "CO", name: "Comp off") }
  # Anchored mid-week; the previous Sunday is an off day under every policy.
  let(:sunday) { Date.new(2027, 7, 4) }

  before { travel_to(Date.new(2027, 7, 7)) }
  after { travel_back }

  def build_request(**attrs)
    build(:comp_off_request, { user: user, date_worked: sunday }.merge(attrs))
  end

  describe "create validations" do
    it "accepts working a weekend and computes the credit" do
      request = build_request
      expect(request).to be_valid
      expect(request.credit_days).to eq(1)
      expect(build_request(half_day: true).credit_days).to eq(BigDecimal("0.5"))
    end

    it "accepts working a holiday that falls on a weekday" do
      create(:holiday, date: Date.new(2027, 7, 6), name: "Festival")
      expect(build_request(date_worked: Date.new(2027, 7, 6))).to be_valid
    end

    it "rejects future dates" do
      request = build_request(date_worked: Date.new(2027, 7, 11))
      expect(request).not_to be_valid
      expect(request.errors[:date_worked].join).to include("future")
    end

    it "rejects regular working days — that's overtime, not comp-off" do
      request = build_request(date_worked: Date.new(2027, 7, 5)) # Monday
      expect(request).not_to be_valid
      expect(request.errors[:date_worked].join).to include("regular working day")
    end

    it "rejects a second request for the same date while one is live" do
      build_request.save!
      dup = build_request
      expect(dup).not_to be_valid
      expect(dup.errors[:date_worked].join).to include("already")
    end

    it "allows re-requesting a date whose earlier request was rejected" do
      first = build_request
      first.save!
      first.reject!(actor: admin, note: "no")
      expect(build_request).to be_valid
    end

    it "requires a reason" do
      expect(build_request(reason: "")).not_to be_valid
    end
  end

  describe "#punch" do
    it "returns the day's attendance record when one exists" do
      record = create(:attendance_record, user: user, date: sunday, check_in_at: sunday.in_time_zone.change(hour: 10))
      expect(build_request.punch).to eq(record)
    end
  end

  describe "#approve!" do
    it "credits the comp-off balance inside the transition and notifies" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      request = build_request
      request.save!

      expect(request.approve!(actor: admin)).to be(true)
      expect(request.reload).to be_approved
      balance = HrLite::LeaveBalance.for(user, co_type, 2027)
      expect(balance.adjustment).to eq(1)
      expect(balance.adjustment_note).to include("comp-off for 2027-07-04")
      expect(bells.map { |b| b[:kind] }).to include("comp_off.approved")
    end

    it "credits 0.5 for a half day" do
      request = build_request(half_day: true)
      request.save!
      request.approve!(actor: admin)
      expect(HrLite::LeaveBalance.for(user, co_type, 2027).adjustment).to eq(BigDecimal("0.5"))
    end

    it "raises MissingCompOffType when no type is flagged" do
      request = build_request
      request.save!
      co_type.update!(comp_off: false)
      expect { request.approve!(actor: admin) }.to raise_error(HrLite::CompOffRequest::MissingCompOffType, /Settings/)
      expect(request.reload).to be_pending
    end

    it "refuses to decide twice — the credit cannot double" do
      request = build_request
      request.save!
      request.approve!(actor: admin)
      expect { request.approve!(actor: admin) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(HrLite::LeaveBalance.for(user, co_type, 2027).adjustment).to eq(1)
    end
  end

  describe "#reject! and #cancel!" do
    it "rejects with the note and notifies the employee" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      request = build_request
      request.save!

      request.reject!(actor: admin, note: "No approval from ops")
      expect(request.reload).to be_rejected
      expect(request.decision_note).to eq("No approval from ops")
      expect(bells.map { |b| b[:kind] }).to include("comp_off.rejected")
    end

    it "cancels a pending request and bells admins" do
      admin # materialize so admin_users finds them
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      request = build_request
      request.save!

      request.cancel!(actor: user)
      expect(request.reload).to be_cancelled
      expect(bells.map { |b| b[:kind] }).to include("comp_off.cancelled")
    end
  end

  it "bells admins on create" do
    admin
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }
    build_request.save!
    requested = bells.select { |b| b[:kind] == "comp_off.requested" }
    expect(requested.map { |b| b[:user] }).to include(admin)
  end
end
