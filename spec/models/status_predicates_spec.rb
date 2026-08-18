require "rails_helper"

# The metaprogrammed `status?` predicates, and the validations nothing had
# reached. Small, but these are the checks other code branches on — a
# predicate that answers wrongly for one status is a silent misroute.
RSpec.describe "Status predicates and unreached validations", no_legacy_bridge: true do
  it "answers every status a regularization ticket can hold" do
    ticket = create(:regularization_request)

    HrLite::RegularizationRequest::STATUSES.each do |status|
      ticket.update_column(:status, status)
      HrLite::RegularizationRequest::STATUSES.each do |other|
        expect(ticket.public_send("#{other}?")).to eq(status == other)
      end
    end
  end

  it "answers every status a comp-off request can hold" do
    request = create(:comp_off_request)

    HrLite::CompOffRequest::STATUSES.each do |status|
      request.update_column(:status, status)
      expect(request.public_send("#{status}?")).to be(true)
    end
  end

  it "answers every status a resignation can hold" do
    resignation = HrLite::Resignation.create!(user: create(:user),
                                              proposed_last_day: Date.current + 30)

    HrLite::Resignation::STATUSES.each do |status|
      resignation.update_column(:status, status)
      expect(resignation.public_send("#{status}?")).to be(true)
    end
  end

  describe HrLite::EmployeeProfile do
    it "refuses a UAN that is not twelve digits" do
      profile = build(:employee_profile, pf_uan: "12345")
      expect(profile).not_to be_valid
      expect(profile.errors[:pf_uan]).to be_present
    end

    it "accepts a blank UAN — not everybody has one" do
      expect(build(:employee_profile, pf_uan: nil)).to be_valid
    end
  end
end

RSpec.describe "Bulk holiday import", type: :request, no_legacy_bridge: true do
  let(:leader) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Boss") }

  before { sign_in leader }

  it "skips blank lines rather than reporting them as errors" do
    expect {
      post "/hr/admin/holidays/bulk_create",
           params: { lines: "2027-01-26, Republic Day\n\n   \n2027-08-15, Independence Day\n" }
    }.to change(HrLite::Holiday, :count).by(2)

    expect(flash[:alert]).to be_blank
  end

  it "says plainly when a paste produced nothing" do
    post "/hr/admin/holidays/bulk_create", params: { lines: "   \n\n" }

    expect(HrLite::Holiday.count).to eq(0)
    expect(response).to redirect_to("/hr/admin/holidays")
  end

  it "names the line that could not be read" do
    post "/hr/admin/holidays/bulk_create",
         params: { lines: "2027-01-26, Republic Day\nnot a date at all\n" }

    expect(HrLite::Holiday.count).to eq(1)
    expect(flash[:alert]).to include("Line 2")
  end
end

RSpec.describe "More unreached branches", no_legacy_bridge: true do
  describe HrLite::LeaveRequest do
    it "answers every status it can hold" do
      leave = create(:leave_request)

      HrLite::LeaveRequest::STATUSES.each do |status|
        leave.update_column(:status, status)
        expect(leave.public_send("#{status}?")).to be(true)
      end
    end
  end

  describe HrLite::PayrollRun do
    it "answers every status it can hold" do
      run = create(:payroll_run)

      HrLite::PayrollRun::STATUSES.each do |status|
        run.update_column(:status, status)
        expect(run.public_send("#{status}?")).to be(true)
      end
    end

    it "is editable only before it is frozen" do
      run = create(:payroll_run)

      %w[draft processing review].each do |status|
        run.update_column(:status, status)
        expect(run).to be_editable
      end
      %w[finalized published].each do |status|
        run.update_column(:status, status)
        expect(run).not_to be_editable
      end
    end
  end

  describe HrLite::Approval do
    it "answers every status it can hold" do
      manager = create(:user)
      employee = create(:user)
      create(:employee_profile, user: employee, manager_id: manager.id)
      flow = HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Leave")
      flow.approval_steps.create!(position: 1, approver_rule: "manager")
      # The engine opens the row itself; creating a second would hit the
      # one-per-approver-per-rung index, which is the point of that index.
      row = create(:leave_request, user: employee).approvals.sole

      described_class::STATUSES.each do |status|
        row.update_column(:status, status)
        expect(row.public_send("#{status}?")).to be(true)
      end
    end
  end

  describe HrLite::SalaryComponent do
    it "answers its kind" do
      HrLite::SalaryComponent.seed_defaults!
      expect(HrLite::SalaryComponent.find_by!(code: "bonus")).to be_earning
      expect(HrLite::SalaryComponent.find_by!(code: "loan_repayment")).to be_deduction
    end
  end

  describe HrLite::Loan do
    it "answers every status it can hold" do
      loan = described_class.create!(user_id: create(:user).id, principal: 1_000,
                                     monthly_instalment: 500, starts_on: Date.current)

      described_class::STATUSES.each do |status|
        loan.update_column(:status, status)
        expect(loan.public_send("#{status}?")).to be(true)
      end
    end
  end
end
