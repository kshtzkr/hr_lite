require "rails_helper"

RSpec.describe HrLite::LeaveRequest do
  let(:user) { create(:user, name: "Asha") }
  let(:type) { create(:leave_type, name: "Casual", annual_quota: 12) }
  # Anchor on a known Monday so weekend math is deterministic.
  let(:monday) { Date.new(2027, 7, 5) }

  before { travel_to(Date.new(2027, 7, 1)) }
  after { travel_back }

  def build_request(**attrs)
    build(:leave_request, { user: user, leave_type: type, start_date: monday, end_date: monday }.merge(attrs))
  end

  describe "create validations" do
    it "accepts a sane request and caches days_count" do
      request = build_request(end_date: monday + 1)
      expect(request).to be_valid
      request.save!
      expect(request.days_count).to eq(2)
    end

    it "rejects inverted ranges and cross-year spans" do
      expect(build_request(end_date: monday - 1)).not_to be_valid
      cross_year = build_request(start_date: Date.new(2027, 12, 30), end_date: Date.new(2028, 1, 2))
      expect(cross_year).not_to be_valid
      expect(cross_year.errors[:base]).to include("Split requests at the year boundary")
    end

    it "rejects multi-day half-days" do
      expect(build_request(half_day: true, end_date: monday + 1)).not_to be_valid
    end

    it "rejects ranges that consume nothing" do
      saturday = build_request(start_date: Date.new(2027, 7, 3), end_date: Date.new(2027, 7, 4))
      expect(saturday).not_to be_valid
      expect(saturday.errors[:base]).to include("Selected dates are all holidays or weekends")
    end

    it "rejects overlaps with own pending or approved requests" do
      create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday + 2)
      overlap = build_request(start_date: monday + 2, end_date: monday + 3)
      expect(overlap).not_to be_valid
      expect(overlap.errors[:base].join).to include("overlapping")
    end

    it "allows overlap with rejected/cancelled requests and other users" do
      create(:leave_request, user: user, leave_type: type, status: "rejected",
             start_date: monday, end_date: monday)
      create(:leave_request, leave_type: type, start_date: monday, end_date: monday)
      expect(build_request).to be_valid
    end

    it "rejects full-day leave over punched dates but allows half-day" do
      create(:attendance_record, :checked_in, user: user, date: monday)
      expect(build_request).not_to be_valid
      expect(build_request(half_day: true)).to be_valid
    end

    it "rejects when balance is insufficient (skipping unlimited types)" do
      small = create(:leave_type, annual_quota: 1)
      create(:leave_request, :approved, user: user, leave_type: small,
             start_date: monday, end_date: monday)
      over = build_request(leave_type: small, start_date: monday + 1, end_date: monday + 1)
      expect(over).not_to be_valid
      expect(over.errors[:base].join).to include("Not enough")

      lwp = create(:leave_type, :unpaid_unlimited)
      expect(build_request(leave_type: lwp, start_date: monday + 1, end_date: monday + 1)).to be_valid
    end
  end

  describe "notifications on create" do
    it "bells admins" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      admin = create(:user, :admin)

      create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)
      requested = bells.select { |b| b[:kind] == "leave.requested" }
      expect(requested.map { |b| b[:user] }).to include(admin)
      expect(requested.first[:title]).to include("Asha applied for Casual")
    end
  end

  describe "#approve!" do
    let(:admin) { create(:user, :admin) }
    let(:request) { create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday) }

    it "approves, stamps the decider and notifies the requester" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }

      expect(request.approve!(actor: admin)).to be(true)
      expect(request.reload).to be_approved
      expect(request.decided_by_id).to eq(admin.id)
      expect(bells.map { |b| b[:kind] }).to include("leave.approved")
    end

    it "refuses when the balance was drained since submission" do
      tight = create(:leave_type, annual_quota: 1)
      first = create(:leave_request, user: user, leave_type: tight, start_date: monday, end_date: monday)
      second = create(:leave_request, user: user, leave_type: tight,
                      start_date: monday + 1, end_date: monday + 1)
      first.approve!(actor: admin)

      expect(second.approve!(actor: admin)).to be(false)
      expect(second.reload).to be_pending
    end

    it "raises on non-pending requests" do
      request.approve!(actor: admin)
      expect { request.approve!(actor: admin) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#reject!" do
    it "stamps the note and notifies" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      admin = create(:user, :admin)
      request = create(:leave_request, user: user, leave_type: type, start_date: monday, end_date: monday)

      request.reject!(actor: admin, note: "Peak season")
      expect(request.reload).to be_rejected
      expect(request.decision_note).to eq("Peak season")
      expect(bells.map { |b| b[:kind] }).to include("leave.rejected")
    end
  end

  describe "#cancel! and #cancellable_by?" do
    let(:admin) { create(:user, :admin) }

    it "owner cancels pending; quota returns automatically for approved-future" do
      request = create(:leave_request, user: user, leave_type: type,
                       start_date: monday, end_date: monday)
      expect(request.cancellable_by?(user)).to be(true)
      expect(request.cancellable_by?(create(:user))).to be(false)

      request.approve!(actor: admin)
      expect(request.reload.cancellable_by?(user)).to be(true) # future approved

      balance = HrLite::LeaveBalance.for(user, type, 2027)
      expect { request.cancel!(actor: user) }.to change { balance.used }.from(1).to(0)
      expect(request.reload).to be_cancelled
    end

    it "cannot cancel past approved leave" do
      request = create(:leave_request, user: user, leave_type: type,
                       start_date: monday, end_date: monday)
      request.approve!(actor: admin)
      travel_to(monday + 1) do
        expect(request.reload.cancellable_by?(user)).to be(false)
      end
    end

    it "notifies admins when an employee cancels" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      create(:user, :admin)
      request = create(:leave_request, user: user, leave_type: type,
                       start_date: monday, end_date: monday)
      request.cancel!(actor: user)
      expect(bells.map { |b| b[:kind] }).to include("leave.cancelled")
    end
  end

  describe "#date_range_label" do
    it "labels single days, half days and ranges" do
      expect(build_request.date_range_label).to eq("05 Jul")
      expect(build_request(half_day: true).date_range_label).to eq("05 Jul (half day)")
      expect(build_request(end_date: monday + 2).date_range_label).to eq("05 Jul – 07 Jul")
    end
  end
end
