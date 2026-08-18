require "rails_helper"

RSpec.describe HrLite::Expense, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let(:category) do
    HrLite::ExpenseCategory.create!(name: "Travel", monthly_cap: 10_000,
                                    receipt_required: false)
  end

  def claim(amount: 2_000, **attrs)
    described_class.create!({ user_id: employee.id, category: category, amount: amount,
                              spent_on: Date.current, description: "Cab to airport" }.merge(attrs))
  end

  describe "the cap" do
    # Told at claim time, not after a week of waiting for an answer.
    it "refuses a claim over what is left this month" do
      claim(amount: 9_000)
      over = described_class.new(user_id: employee.id, category: category, amount: 2_000,
                                 spent_on: Date.current, description: "Another cab")

      expect(over).not_to be_valid
      expect(over.errors[:amount].join).to include("over the Travel cap")
    end

    it "counts a claim still awaiting a decision against the cap" do
      claim(amount: 9_000).update!(status: "submitted")
      expect(category.remaining_for(employee)).to eq(1_000)
    end

    # A refused claim was never spent.
    it "gives the room back when a claim is rejected" do
      claim(amount: 9_000).update!(status: "rejected")
      expect(category.remaining_for(employee)).to eq(10_000)
    end

    it "does not cap an uncapped category" do
      free = HrLite::ExpenseCategory.create!(name: "Medical", receipt_required: false)
      expect(free.remaining_for(employee)).to be_nil
      expect(described_class.new(user_id: employee.id, category: free, amount: 500_000,
                                 spent_on: Date.current, description: "Surgery")).to be_valid
    end

    it "counts each month separately" do
      claim(amount: 9_000, spent_on: Date.current.prev_month.beginning_of_month)
      expect(category.remaining_for(employee)).to eq(10_000)
    end
  end

  describe "a receipt" do
    let(:strict) { HrLite::ExpenseCategory.create!(name: "Entertainment", receipt_required: true) }

    it "is required when the category says so" do
      expense = described_class.new(user_id: employee.id, category: strict, amount: 500,
                                    spent_on: Date.current, description: "Client dinner")
      expect(expense).not_to be_valid
      expect(expense.errors[:receipt].join).to include("required")
    end

    it "satisfies the rule once attached" do
      expense = described_class.new(user_id: employee.id, category: strict, amount: 500,
                                    spent_on: Date.current, description: "Client dinner")
      expense.receipt.attach(io: StringIO.new("x"), filename: "r.pdf",
                             content_type: "application/pdf")
      expect(expense).to be_valid
    end
  end

  describe "validation" do
    it "refuses a future date and a non-positive amount" do
      expect(described_class.new(user_id: employee.id, category: category, amount: 100,
                                 spent_on: Date.current + 1, description: "x")).not_to be_valid
      expect(described_class.new(user_id: employee.id, category: category, amount: 0,
                                 spent_on: Date.current, description: "x")).not_to be_valid
    end
  end

  describe "the lifecycle" do
    it "submits, approves and then reimburses with a payroll month" do
      expense = claim
      expense.submit!(actor: employee)
      expect(expense.reload).to be_submitted

      expense.approve!(actor: finance)
      expect(expense.reload).to be_approved

      expense.reimburse!(actor: finance, period_month: Date.new(2027, 6, 1))
      expect(expense.reload).to be_reimbursed
      expect(expense.reimbursed_in).to eq(Date.new(2027, 6, 1))
    end

    # Agreeing to pay somebody and paying them are different days, and the
    # person waiting cares about the second one.
    it "will not reimburse something nobody approved" do
      expect { claim.reimburse!(actor: finance, period_month: Date.current) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses a rejection with no reason" do
      expect { claim.reject!(actor: finance, note: "") }.to raise_error(ArgumentError)
    end

    it "lets a rejected claim be corrected and resubmitted" do
      expense = claim
      expense.submit!(actor: employee)
      expense.reject!(actor: finance, note: "No receipt")

      expect(expense.reload).to be_rejected
      expect { expense.submit!(actor: employee) }.not_to raise_error
    end
  end

  describe "routed through the approval engine" do
    before do
      flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::Expense", name: "Expenses")
      flow.approval_steps.create!(position: 1, approver_rule: "manager")
      flow.approval_steps.create!(position: 2, approver_rule: "permission",
                                  approver_key: "expense.approve")
      create(:employee_profile, user: employee, manager_id: manager.id)
    end

    # The point of #20: a fifth module gets multi-level approval for free.
    it "needs the manager first, then finance" do
      expense = claim
      expect(expense.pending_approvals.map(&:approver_id)).to eq([ manager.id ])

      expense.approve!(actor: manager)
      expect(expense.reload).not_to be_approved

      expense.approve!(actor: finance)
      expect(expense.reload).to be_approved
    end
  end
end

RSpec.describe HrLite::Benefit, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  let(:benefit) do
    described_class.create!(name: "Group health", kind: "health", provider: "Acme Insure",
                            coverage: 500_000, employer_premium: 12_000,
                            effective_from: Date.current - 30, expires_on: Date.current + 300)
  end

  it "knows which policies are live today" do
    benefit
    described_class.create!(name: "Lapsed", kind: "life", effective_from: Date.current - 400,
                            expires_on: Date.current - 1)

    expect(described_class.live_on(Date.current)).to contain_exactly(benefit)
  end

  it "flags a policy about to lapse" do
    soon = described_class.create!(name: "Accident", kind: "accident",
                                   expires_on: Date.current + 10)
    expect(soon).to be_expiring
    expect(benefit).not_to be_expiring
  end

  it "refuses an expiry before the start" do
    expect(described_class.new(name: "X", effective_from: Date.current,
                               expires_on: Date.current - 1)).not_to be_valid
  end

  describe "enrolment" do
    it "records cover from a date, with a dependant count and no family data" do
      enrolment = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                                    enrolled_on: Date.current - 10, dependants: 3)

      expect(enrolment).to be_live
      expect(HrLite::BenefitEnrolment.column_names).not_to include("dependant_names")
    end

    it "refuses enrolling the same person twice" do
      HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                        enrolled_on: Date.current)
      expect(HrLite::BenefitEnrolment.new(benefit: benefit, user_id: employee.id,
                                           enrolled_on: Date.current)).not_to be_valid
    end

    it "stops being live once it has ended" do
      enrolment = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                                    enrolled_on: Date.current - 10,
                                                    ended_on: Date.current - 1)
      expect(enrolment).not_to be_live
    end

    it "refuses an end before the start" do
      expect(HrLite::BenefitEnrolment.new(benefit: benefit, user_id: employee.id,
                                           enrolled_on: Date.current,
                                           ended_on: Date.current - 1)).not_to be_valid
    end
  end
end

RSpec.describe HrLite::HrRequest, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  def request!(**attrs)
    described_class.create!({ user_id: employee.id, category: "salary_certificate",
                              subject: "Certificate for a visa" }.merge(attrs))
  end

  it "bells the desk when it is raised" do
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }
    request!

    expect(bells.map { |b| b[:user] }).to include(hr)
  end

  it "assigns, then resolves back to the person who asked" do
    bells = []
    req = request!
    HrLite.config.notify = ->(**kw) { bells << kw }

    req.assign!(actor: hr, assignee: hr)
    expect(req.reload).to be_in_progress

    req.resolve!(actor: hr, resolution: "Attached, signed.")
    expect(req.reload).to be_resolved
    expect(req.resolution).to eq("Attached, signed.")
    expect(bells.map { |b| b[:user] }).to include(employee)
  end

  it "refuses a resolution with no answer in it" do
    expect { request!.resolve!(actor: hr, resolution: " ") }.to raise_error(ArgumentError)
  end

  it "refuses an unknown category" do
    expect(described_class.new(user_id: employee.id, category: "wat", subject: "x")).not_to be_valid
  end

  it "cannot be cancelled once it is settled" do
    req = request!
    req.resolve!(actor: hr, resolution: "Done")
    expect { req.cancel!(actor: employee) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

RSpec.describe HrLite::Policy, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  def policy!(**attrs)
    described_class.create!({ title: "Code of conduct", body: "Be decent.",
                              effective_from: Date.current, published: true,
                              acknowledgement_required: true }.merge(attrs))
  end

  it "records an acknowledgement once, however many times somebody clicks" do
    policy = policy!
    policy.acknowledge!(employee)
    policy.acknowledge!(employee)

    expect(policy.policy_acknowledgements.count).to eq(1)
    expect(policy).to be_acknowledged_by(employee)
  end

  it "never lets an acknowledgement be edited — it is the evidence" do
    policy = policy!
    ack = policy.acknowledge!(employee)

    expect(ack).to be_readonly
  end

  # An acknowledgement of v1 says nothing about v2.
  it "asks everybody again when it is re-issued" do
    v1 = policy!
    v1.acknowledge!(employee)
    create(:employee_profile, user: employee)

    v2 = v1.supersede!(body: "Be decent, and be on time.")

    expect(v2.version).to eq(2)
    expect(v2).not_to be_acknowledged_by(employee)
    expect(v2.outstanding_for).to include(employee)
    expect(v1.reload).to be_acknowledged_by(employee)
  end

  it "shows only the newest version in force" do
    v1 = policy!
    v1.supersede!(body: "v2")

    expect(described_class.current.map(&:version)).to eq([ 2 ])
  end

  it "asks nobody when acknowledgement is not required" do
    expect(policy!(acknowledgement_required: false).outstanding_for).to be_empty
  end

  it "asks nobody while it is unpublished" do
    expect(policy!(published: false).outstanding_for).to be_empty
  end
end

RSpec.describe "Employee-service edges", no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:manager) { user_with_roles(HrLite::Role::MANAGER, name: "Asha") }
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }

  it "lists the enrolments live on a date" do
    benefit = HrLite::Benefit.create!(name: "Health", kind: "health")
    live = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                            enrolled_on: Date.current - 5)
    HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: manager.id,
                                      enrolled_on: Date.current - 40,
                                      ended_on: Date.current - 10)

    expect(HrLite::BenefitEnrolment.live_on(Date.current)).to contain_exactly(live)
  end

  it "cancels an open HR request" do
    request = HrLite::HrRequest.create!(user_id: employee.id, category: "other",
                                        subject: "Never mind")
    request.cancel!(actor: employee)

    expect(request.reload).to be_cancelled
  end

  it "returns the existing acknowledgement when two requests race" do
    policy = HrLite::Policy.create!(title: "Travel", body: "Book early.",
                                    effective_from: Date.current, published: true,
                                    acknowledgement_required: true)
    first = policy.acknowledge!(employee)
    # Both callers get past find_or_create_by before either commits; the
    # unique index refuses the loser, who then reads the winner's row.
    allow(policy.policy_acknowledgements).to receive(:find_or_create_by!)
      .and_raise(ActiveRecord::RecordNotUnique)

    expect(policy.acknowledge!(employee)).to eq(first)
  end

  # The refusal ends the claim at the rung it was refused on, and the reason
  # travels with it.
  it "records a routed rejection with the approver's reason" do
    create(:employee_profile, user: employee, manager_id: manager.id)
    flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::Expense", name: "Expenses")
    flow.approval_steps.create!(position: 1, approver_rule: "manager")
    flow.approval_steps.create!(position: 2, approver_rule: "permission",
                                approver_key: "expense.approve")
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    expense = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 100,
                                      spent_on: Date.current, description: "Cab")

    expense.reject!(actor: manager, note: "Take the metro")

    expect(expense.reload).to be_rejected
    expect(expense.decision_note).to eq("Take the metro")
    expect(expense.approvals.pending).to be_empty
  end
end

RSpec.describe "Guard paths in the new services", no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }

  it "never calls a benefit with no expiry date 'expiring'" do
    expect(HrLite::Benefit.create!(name: "Life", kind: "life", expires_on: nil))
      .not_to be_expiring
  end

  it "does not call an already-lapsed policy 'expiring'" do
    expect(HrLite::Benefit.create!(name: "Old", kind: "life", expires_on: Date.current - 1))
      .not_to be_expiring
  end

  it "refuses to submit a claim that is already settled" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    expense = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 100,
                                      spent_on: Date.current, description: "Cab")
    expense.submit!(actor: employee)
    expense.approve!(actor: finance)

    expect { expense.submit!(actor: employee) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "has no current policies when none are published" do
    HrLite::Policy.create!(title: "Draft", body: "x", effective_from: Date.current,
                           published: false)
    expect(HrLite::Policy.current).to be_empty
  end

  it "ignores a policy that has not taken effect yet" do
    HrLite::Policy.create!(title: "Future", body: "x", effective_from: Date.current + 30,
                           published: true)
    expect(HrLite::Policy.current).to be_empty
  end
end

RSpec.describe "A few more guards", no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "treats an enrolment with no end date as open-ended" do
    benefit = HrLite::Benefit.create!(name: "Health", kind: "health")
    enrolment = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                                  enrolled_on: Date.current - 1, ended_on: nil)
    expect(enrolment).to be_live
    expect(enrolment.live?(Date.current + 3650)).to be(true)
  end

  it "does not treat an enrolment as live before it starts" do
    benefit = HrLite::Benefit.create!(name: "Health", kind: "health")
    enrolment = HrLite::BenefitEnrolment.create!(benefit: benefit, user_id: employee.id,
                                                  enrolled_on: Date.current + 10)
    expect(enrolment).not_to be_live
  end

  it "keeps the acknowledgement flag from the version it supersedes" do
    policy = HrLite::Policy.create!(title: "Remote work", body: "v1",
                                    effective_from: Date.current, published: true,
                                    acknowledgement_required: true)
    expect(policy.supersede!(body: "v2").acknowledgement_required).to be(true)
  end

  it "lets a re-issue change whether acknowledgement is required" do
    policy = HrLite::Policy.create!(title: "Remote work", body: "v1",
                                    effective_from: Date.current, published: true,
                                    acknowledgement_required: true)
    expect(policy.supersede!(body: "v2", acknowledgement_required: false)
                 .acknowledgement_required).to be(false)
  end
end
