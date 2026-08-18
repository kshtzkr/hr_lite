require "rails_helper"

# Four modules had each grown their own approve/reject/cancel. This is the one
# engine they move onto — and the first thing it has to prove is that a model
# with NO flow configured behaves exactly as it always did, because that is
# what lets them migrate one at a time.
RSpec.describe "Routed approvals", no_legacy_bridge: true do
  # let! rather than let: a `permission` rung resolves its approvers at the
  # moment the request is raised, so somebody who does not exist yet is a
  # rung with nobody on it — which the engine correctly skips.
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, code: "CL", name: "Casual", annual_quota: 12) }

  # Thursday 17 June 2027. Leave lands on the Monday and Tuesday after —
  # `Date.current + 9` is a weekend on most days of the week, and leave that
  # covers no working day is refused at creation.
  around { |example| travel_to(Date.new(2027, 6, 17)) { example.run } }

  before { create(:employee_profile, user: employee, manager_id: manager.id) }

  def flow_with(*steps)
    flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
    steps.each_with_index do |step, index|
      flow.approval_steps.create!(position: index + 1, **step)
    end
    flow
  end

  def leave_for(user = employee)
    create(:leave_request, user: user, leave_type: leave_type,
                           start_date: Date.new(2027, 6, 21), end_date: Date.new(2027, 6, 21))
  end

  describe "with no flow configured" do
    it "settles on the first approval, exactly as before" do
      leave = leave_for
      expect(leave.routed_for_approval?).to be(false)

      leave.approve!(actor: hr)
      expect(leave.reload).to be_approved
    end
  end

  describe "manager then HR" do
    before do
      flow_with({ approver_rule: "manager" },
                { approver_rule: "permission", approver_key: "leave.approve" })
    end

    it "opens on the manager and nobody else" do
      leave = leave_for

      expect(leave.pending_approvals.map(&:approver_id)).to eq([ manager.id ])
      expect(leave.awaiting?(manager)).to be(true)
      expect(leave.awaiting?(hr)).to be(false)
    end

    it "stays pending after the first rung, then approves on the last" do
      leave = leave_for

      leave.approve!(actor: manager, note: "fine by me")
      expect(leave.reload).to be_pending
      expect(leave.pending_approvals.map(&:approver_id)).to contain_exactly(hr.id, owner.id)

      leave.approve!(actor: hr)
      expect(leave.reload).to be_approved
      expect(leave.pending_approvals).to be_empty
    end

    it "credits the balance only once, on the final rung" do
      leave = leave_for
      used_before = leave.balance.used

      leave.approve!(actor: manager)
      expect(leave.balance.used).to eq(used_before)

      leave.approve!(actor: hr)
      expect(leave.balance.used).to be > used_before
    end

    it "ends the whole thing on one refusal" do
      leave = leave_for
      leave.reject!(actor: manager, note: "peak season")

      expect(leave.reload).to be_rejected
      expect(leave.approvals.pending).to be_empty
      # The later rung was never opened, so there is nothing to cancel — a
      # refusal ends the request before HR is ever asked.
      expect(leave.approvals.map(&:position)).to eq([ 1 ])
      expect(leave.approvals.sole.status).to eq("rejected")
    end

    it "keeps the full history, rung by rung" do
      leave = leave_for
      leave.approve!(actor: manager, note: "ok")
      leave.approve!(actor: hr, note: "approved")

      history = leave.approval_history.map { |a| [ a.position, a.status ] }
      expect(history.first).to eq([ 1, "approved" ])
      expect(history.map(&:last)).to include("approved")
    end

    # HR holds leave.approve at `all`, so they can still act directly. The
    # routed path is the normal one, not the only one.
    it "lets somebody outside the current rung settle it outright" do
      leave = leave_for
      expect(leave.awaiting?(hr)).to be(false)

      leave.approve!(actor: hr)
      expect(leave.reload).to be_approved
    end
  end

  describe "a rung nobody occupies" do
    # An employee with no manager recorded would otherwise wait forever on a
    # person who does not exist.
    it "is skipped rather than left waiting" do
      flow_with({ approver_rule: "manager" },
                { approver_rule: "permission", approver_key: "leave.approve" })
      orphan = user_with_roles(HrLite::Role::EMPLOYEE, name: "Nobody")
      create(:employee_profile, user: orphan, manager_id: nil)

      leave = leave_for(orphan)

      expect(leave.pending_approvals.map(&:approver_id)).to contain_exactly(hr.id, owner.id)
    end

    it "approves outright when every rung is empty" do
      flow_with({ approver_rule: "manager" })
      orphan = user_with_roles(HrLite::Role::EMPLOYEE, name: "Nobody")
      create(:employee_profile, user: orphan, manager_id: nil)

      expect(HrLite::ApprovalRoute.new(leave_for(orphan)).pending_rows).to be_empty
    end
  end

  describe "a unanimous rung" do
    it "waits for everybody on it" do
      flow_with({ approver_rule: "permission", approver_key: "leave.approve", unanimous: true })
      leave = leave_for

      expect(leave.pending_approvals.count).to eq(2) # hr + owner

      leave.approve!(actor: hr)
      expect(leave.reload).to be_pending

      leave.approve!(actor: owner)
      expect(leave.reload).to be_approved
    end
  end

  describe "one refusal on a unanimous rung" do
    # The others are still pending when the refusal lands, so they have to be
    # stood down — otherwise a rejected request keeps asking people to decide.
    it "stands the rest of the rung down" do
      flow_with({ approver_rule: "permission", approver_key: "leave.approve", unanimous: true })
      leave = leave_for
      expect(leave.pending_approvals.count).to eq(2)

      leave.reject!(actor: hr, note: "no")

      expect(leave.reload).to be_rejected
      expect(leave.approvals.pending).to be_empty
      expect(leave.approvals.map(&:status)).to contain_exactly("rejected", "cancelled")
    end
  end

  describe "delegation" do
    it "lets a stand-in answer while the approver is away" do
      flow_with({ approver_rule: "manager" })
      stand_in = user_with_roles(HrLite::Role::EMPLOYEE, name: "Priya")
      HrLite::ApprovalDelegation.create!(from_user: manager, to_user: stand_in,
                                          starts_on: Date.current, ends_on: Date.current + 7,
                                          reason: "Asha on leave")
      leave = leave_for

      expect(leave.awaiting?(stand_in)).to be(true)
      leave.approve!(actor: stand_in)

      expect(leave.reload).to be_approved
      expect(leave.approvals.first.decided_by_id).to eq(stand_in.id)
      expect(leave.approvals.first.approver_id).to eq(manager.id)
    end

    it "does not apply outside the delegation window" do
      flow_with({ approver_rule: "manager" })
      stand_in = user_with_roles(HrLite::Role::EMPLOYEE, name: "Priya")
      HrLite::ApprovalDelegation.create!(from_user: manager, to_user: stand_in,
                                          starts_on: Date.current - 10, ends_on: Date.current - 3)

      expect(leave_for.awaiting?(stand_in)).to be(false)
    end

    it "refuses a delegation to oneself, or one that ends before it starts" do
      expect(HrLite::ApprovalDelegation.new(from_user: manager, to_user: manager,
                                             starts_on: Date.current, ends_on: Date.current)).not_to be_valid
      expect(HrLite::ApprovalDelegation.new(from_user: manager, to_user: hr,
                                             starts_on: Date.current, ends_on: Date.current - 1)).not_to be_valid
    end
  end

  describe "the other approver rules" do
    let!(:skip_level) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Director") }

    before { create(:employee_profile, user: manager, manager_id: skip_level.id) }

    it "reaches the manager's manager" do
      flow_with({ approver_rule: "manager_of_manager" })
      expect(leave_for.pending_approvals.map(&:approver_id)).to eq([ skip_level.id ])
    end

    it "reaches one named person" do
      flow_with({ approver_rule: "user", approver_key: hr.id.to_s })
      expect(leave_for.pending_approvals.map(&:approver_id)).to eq([ hr.id ])
    end

    it "describes each rung in words the person configuring it can read" do
      flow = flow_with({ approver_rule: "manager" },
                       { approver_rule: "manager_of_manager" },
                       { approver_rule: "permission", approver_key: "leave.approve" },
                       { approver_rule: "user", approver_key: hr.id.to_s })
      expect(flow.approval_steps.ordered.map(&:label))
        .to eq([ "Their manager", "Their manager's manager",
                 "Anyone who can approve, reject and cancel leave and comp-off", "Chitra" ])
    end

    it "refuses a `user` rung that names nobody" do
      flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
      expect(flow.approval_steps.new(position: 1, approver_rule: "user")).not_to be_valid
    end
  end

  describe "cancelling the request" do
    # An approval left pending on a request that has been called off sits in
    # somebody's inbox for ever.
    it "stands the outstanding approvals down" do
      flow_with({ approver_rule: "manager" })
      leave = leave_for

      expect(leave.pending_approvals).not_to be_empty
      leave.cancel!(actor: employee)

      expect(leave.reload.pending_approvals).to be_empty
      expect(leave.approvals.first.status).to eq("cancelled")
    end
  end

  describe "a rejection with no note" do
    it "still records why the request ended" do
      flow_with({ approver_rule: "manager" })
      leave = leave_for
      leave.reject!(actor: manager, note: nil)

      expect(leave.reload).to be_rejected
      expect(leave.decision_note).to eq("Rejected")
    end
  end

  describe "a step whose `user` has since been deleted" do
    it "is treated as a rung nobody occupies" do
      flow_with({ approver_rule: "user", approver_key: "999999" },
                { approver_rule: "manager" })

      expect(leave_for.pending_approvals.map(&:approver_id)).to eq([ manager.id ])
    end
  end

  describe "the flow definition" do
    it "refuses a subject type the engine cannot route" do
      flow = HrLite::ApprovalFlow.new(subject_type: "HrLite::PayrollRun", name: "Payroll")
      expect(flow).not_to be_valid
      expect(flow.errors[:subject_type].join).to include("not a type this engine can route")
    end

    it "refuses a step naming a permission nobody declared" do
      flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
      step = flow.approval_steps.new(position: 1, approver_rule: "permission",
                                     approver_key: "leave.aprove")
      expect(step).not_to be_valid
    end

    it "allows only one active flow per subject type" do
      flow_with({ approver_rule: "manager" })
      expect {
        HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Second")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end

RSpec.describe HrLite::Approval, no_legacy_bridge: true do
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:leave_type) { create(:leave_type, code: "CL", annual_quota: 12) }

  around { |example| travel_to(Date.new(2027, 6, 17)) { example.run } }

  def approval(sla: 24)
    create(:employee_profile, user: employee, manager_id: manager.id)
    flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
    flow.approval_steps.create!(position: 1, approver_rule: "manager", sla_hours: sla)
    create(:leave_request, user: employee, leave_type: leave_type,
                           start_date: Date.new(2027, 6, 21), end_date: Date.new(2027, 6, 21))
      .approvals.first
  end

  describe "#answerable_by?" do
    it "is nobody's when the row is already decided" do
      row = approval
      row.decide!(status: "approved", actor: manager)

      expect(row.answerable_by?(manager)).to be(false)
    end

    it "is false for nil and for a stranger" do
      row = approval
      expect(row.answerable_by?(nil)).to be(false)
      expect(row.answerable_by?(employee)).to be(false)
    end
  end

  describe "#overdue?" do
    it "is never overdue without a deadline on the step" do
      row = approval(sla: nil)
      row.update_column(:created_at, 30.days.ago)

      expect(row.overdue?).to be(false)
    end

    it "is not overdue once it has been decided" do
      row = approval
      row.update_column(:created_at, 30.days.ago)
      row.decide!(status: "approved", actor: manager)

      expect(row.overdue?).to be(false)
    end

    it "refuses a decision it does not recognise" do
      expect { approval.decide!(status: "maybe", actor: manager) }
        .to raise_error(ArgumentError, /unknown decision/)
    end
  end

  describe HrLite::ApprovalDelegation, ".stand_ins_for" do
    it "follows a second hop when the stand-in is also away" do
      a = create(:user, name: "A")
      b = create(:user, name: "B")
      c = create(:user, name: "C")
      described_class.create!(from_user: a, to_user: b,
                              starts_on: Date.current, ends_on: Date.current + 3)
      described_class.create!(from_user: b, to_user: c,
                              starts_on: Date.current, ends_on: Date.current + 3)

      expect(described_class.stand_ins_for(a.id)).to contain_exactly(b.id, c.id)
    end

    it "never hands somebody their own approvals back through a loop" do
      a = create(:user, name: "A")
      b = create(:user, name: "B")
      described_class.create!(from_user: a, to_user: b,
                              starts_on: Date.current, ends_on: Date.current + 3)
      described_class.create!(from_user: b, to_user: a,
                              starts_on: Date.current, ends_on: Date.current + 3)

      expect(described_class.stand_ins_for(a.id)).to eq([ b.id ])
    end
  end

  describe HrLite::ApprovalFlow, ".for" do
    it "ignores a flow that has been switched off" do
      HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest",
                                   name: "Old", active: false)
      expect(described_class.for("HrLite::LeaveRequest")).to be_nil
    end
  end
end
