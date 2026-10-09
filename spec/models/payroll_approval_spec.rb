require "rails_helper"
require Rails.root.join("../../db/migrate/20261010100200_grant_hr_lite_payroll_approve.rb")

RSpec.describe "Payroll approval", no_legacy_bridge: true do
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:hr2) { user_with_roles(HrLite::Role::HR, name: "Ira") }
  let(:bells) { [] }
  let(:run) do
    create(:salary_structure, user: create(:employee_profile).user)
    create(:payroll_run).tap { |r| r.compute!(actor: owner) }
  end

  before { HrLite.config.notify = ->(**kw) { bells << kw } }

  it "takes two different approvers, one of them able to run payroll, and the second publishes" do
    run.approve!(actor: hr)
    expect([ run.reload.status, run.first_approved_by_id ]).to eq([ "review", hr.id ])
    expect(bells.select { |b| b[:kind] == "payroll.approval_needed" }.map { |b| b[:user] }).to include(owner)

    expect { run.approve!(actor: hr) }.to raise_error(ActiveRecord::RecordInvalid, /second, different approver/)
    expect { run.approve!(actor: hr2) }.to raise_error(ActiveRecord::RecordInvalid, /second, different approver/)
    expect { run.approve!(actor: user_with_roles(HrLite::Role::MANAGER)) }.to raise_error(ActiveRecord::RecordInvalid, /not an approver/)

    run.approve!(actor: owner)
    expect(run.reload).to have_attributes(status: "published", finalized_by_id: owner.id, published_by_id: owner.id)
  end

  it "forgets the first approval when the run is recomputed" do
    run.approve!(actor: hr)
    run.compute!(actor: owner)
    expect(run.reload.first_approved_by_id).to be_nil
  end

  it "auto-approves a clean run on the 3rd, and leaves one with blocking warnings for people" do
    run.update!(warnings: []) # clean: the shipped card can be a year behind this spec's clock
    HrLite::PayrollAutoApproveJob.perform_now(month: run.period_month)
    expect(run.reload).to have_attributes(status: "published", finalized_by_id: nil)
    expect(run.auto_approved_at).to be_present

    stale = create(:payroll_run, period_month: run.period_month.prev_month.prev_month, status: "review",
                                 warnings: [ "Payroll for FY 2027-28 is being computed on the FY 2026-27 statutory card — no card ships for FY 2027-28 yet." ])
    expect(stale.auto_approve!).to be(false)

    stuck = create(:payroll_run, period_month: run.period_month.prev_month, status: "review",
                                 warnings: [ "No salary structure for Dev — skipped" ])
    hr
    HrLite::PayrollAutoApproveJob.perform_now(month: stuck.period_month)
    expect(stuck.reload).to be_review
    expect(bells.find { |b| b[:kind] == "payroll.overdue" }).to include(title: /overdue — not auto-approved: No salary structure for Dev/)
    expect(HrLite::PayrollAutoApproveJob.perform_now(month: Date.new(2020, 1, 1))).to be_nil
  end

  it "warns when leave or attendance fixes for the month are still pending" do
    leave_month = run.period_month
    create(:leave_request, user: create(:user), start_date: leave_month + 2, end_date: leave_month + 2)
    run.compute!(actor: owner)
    expect(run.reload.warnings.last).to start_with("1 leave or attendance request is still pending")
  end

  it "grants HR and Super Admin on an install that already has its roles" do
    hr_role = HrLite::Role.find_by!(name: HrLite::Role::HR)
    HrLite::RoleGrant.where(role: hr_role, permission_key: %w[payroll.approve salary.manage profile.manage]).delete_all
    hr_role.role_grants.find_by!(permission_key: "payroll.view").update!(scope: "self")
    HrLite::Role.where.not(name: [ HrLite::Role::HR, HrLite::Role::SUPER_ADMIN ]).delete_all

    GrantHrLitePayrollApprove.new.tap { |m| m.verbose = false }.up
    grants = hr_role.role_grants.reload.to_h { |g| [ g.permission_key, g.scope ] }
    expect(grants.slice("payroll.approve", "payroll.view", "salary.manage", "profile.manage").values).to all(eq("all"))
  end
end
