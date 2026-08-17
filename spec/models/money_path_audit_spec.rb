require "rails_helper"

# Every transition that moves money, or hands it to someone, has to leave a
# row behind. Before this spec the payroll lifecycle wrote nothing at all:
# a run could be computed, finalized, unlocked, edited and republished, and
# the audit screen showed none of it.
RSpec.describe "Money-path audit trail" do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:month) { Date.new(2027, 6, 1) }

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  def payroll_rows(action)
    HrLite::AuditLog.where(subject_type: "HrLite::PayrollRun", action: action)
  end

  describe "payroll run lifecycle" do
    let(:run) do
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      create(:payroll_run, period_month: month)
    end

    it "records every transition with its actor and period" do
      run.compute!(actor: leader)
      run.finalize!(actor: leader)
      run.unlock!(actor: leader)
      run.finalize!(actor: leader)
      run.publish!(actor: leader)

      actions = HrLite::AuditLog.where(subject_type: "HrLite::PayrollRun").pluck(:action)
      expect(actions).to contain_exactly(
        "payroll.computed", "payroll.finalized", "payroll.unlocked",
        "payroll.finalized", "payroll.published"
      )

      row = payroll_rows("payroll.published").sole
      expect(row.actor_id).to eq(leader.id)
      expect(row.subject_id).to eq(run.id)
      expect(row.audited_changes).to include("period" => "June 2027", "slips" => 1)
    end

    it "keeps amounts out of the row — audit_logs is not encrypted" do
      run.compute!(actor: leader)
      run.finalize!(actor: leader)

      serialized = HrLite::AuditLog.where(subject_type: "HrLite::PayrollRun")
                                   .pluck(:audited_changes).to_json
      net = run.total_net.to_i.to_s
      expect(serialized).not_to include(net)
    end

    it "rolls the transition back when the audit row cannot be written" do
      run.compute!(actor: leader)
      allow(HrLite::AuditLog).to receive(:record!).and_raise(ActiveRecord::RecordInvalid.new(HrLite::AuditLog.new))

      expect { run.finalize!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(run.reload.status).to eq("review")
    end

    it "hides payroll rows from the leadership audit screen" do
      run.compute!(actor: leader)
      expect(HrLite::AuditLog.outside_money_tier.where(subject_type: "HrLite::PayrollRun")).to be_empty
    end
  end

  describe "the payout register download", type: :request do
    it "audits the export itself, bank details and all" do
      profile = create(:employee_profile)
      create(:salary_structure, user: profile.user)
      run = create(:payroll_run, period_month: month)
      run.compute!(actor: leader)

      HrLite.config.leadership_emails = [ leader.email ]
      sign_in leader
      get "/hr/admin/payroll_runs/#{run.id}/register"

      expect(response).to have_http_status(:ok)
      row = HrLite::AuditLog.find_by(action: "payroll.register_exported")
      expect(row.actor_id).to eq(leader.id)
      expect(row.audited_changes).to include("rows" => 1, "includes_bank_details" => true)
    end
  end

  describe "leave decisions" do
    let(:employee) { create(:employee_profile).user }
    let(:type) { create(:leave_type, annual_quota: 12) }

    def request_for(user)
      create(:leave_request, user: user, leave_type: type,
                             start_date: Date.new(2027, 7, 12), end_date: Date.new(2027, 7, 12))
    end

    it "records an approval with who, whose, which type and how long" do
      leave = request_for(employee)
      leave.approve!(actor: leader, note: "fine")

      row = HrLite::AuditLog.find_by(action: "leave.approved")
      expect(row.actor_id).to eq(leader.id)
      expect(row.subject_id).to eq(leave.id)
      expect(row.audited_changes).to include(
        "employee" => HrLite.display_name(employee), "type" => type.code, "note" => "fine"
      )
    end

    it "records a rejection" do
      request_for(employee).reject!(actor: leader, note: "peak season")
      expect(HrLite::AuditLog.find_by(action: "leave.rejected").audited_changes["note"])
        .to eq("peak season")
    end

    it "records a cancellation and says whether days were handed back" do
      leave = request_for(employee)
      leave.approve!(actor: leader)
      leave.cancel!(actor: employee)

      expect(HrLite::AuditLog.find_by(action: "leave.cancelled").audited_changes["note"])
        .to eq("was approved")
    end

    it "never copies the employee's own reason into the trail" do
      leave = create(:leave_request, user: employee, leave_type: type,
                                     start_date: Date.new(2027, 7, 12), end_date: Date.new(2027, 7, 12),
                                     reason: "surgery consultation")
      leave.approve!(actor: leader)

      expect(HrLite::AuditLog.pluck(:audited_changes).to_json).not_to include("surgery")
    end

    it "leaves the request pending when its audit row cannot be written" do
      leave = request_for(employee)
      allow(HrLite::AuditLog).to receive(:record!).and_raise(ActiveRecord::RecordInvalid.new(HrLite::AuditLog.new))

      expect { leave.approve!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(leave.reload.status).to eq("pending")
    end
  end

  describe HrLite::AuditLog, ".record!" do
    # The admin attendance screen audits a punch it decided NOT to save
    # (a correction that removed the day), so the subject has no id at all.
    it "still records a subject that was never saved" do
      row = described_class.record!(action: "destroy", subject: HrLite::AttendanceRecord.new,
                                    actor: leader)
      expect(row.subject_id).to eq(0)
      expect(row.subject_type).to eq("HrLite::AttendanceRecord")
    end

    it "defaults the actor to the current request's actor" do
      HrLite::Current.actor = leader
      row = described_class.record!(action: "x", subject: create(:leave_type))
      expect(row.actor_id).to eq(leader.id)
    ensure
      HrLite::Current.actor = nil
    end
  end
end
