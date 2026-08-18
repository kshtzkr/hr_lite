require "rails_helper"

# Statuses are plain strings validated only in Ruby, so every write path that
# skips validations — update_column, update_all, insert_all, a console fix —
# could put a value in the column that no screen renders and no transition
# accepts. These examples bypass the model exactly the way those paths do,
# and prove the DATABASE refuses.
RSpec.describe "Status values are enforced by the database" do
  def expect_refused
    expect { yield }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "refuses a bogus leave-request status" do
    leave = create(:leave_request)
    expect_refused { leave.update_column(:status, "approvedd") }
  end

  it "refuses a bogus payroll-run status" do
    run = create(:payroll_run)
    # "locked" is from the roadmap, not the model — the constraint is what
    # stops a half-shipped lifecycle leaking into live rows.
    expect_refused { run.update_column(:status, "locked") }
  end

  it "refuses a bogus attendance status" do
    record = create(:attendance_record)
    expect_refused { record.update_column(:status, "wfh") }
  end

  it "refuses a bogus resignation status" do
    resignation = HrLite::Resignation.create!(user: create(:user),
                                              proposed_last_day: Date.current + 30)
    expect_refused { resignation.update_column(:status, "accepted_maybe") }
  end

  it "refuses a bogus appraisal status" do
    appraisal = create(:appraisal)
    expect_refused { appraisal.update_column(:status, "published") }
  end

  it "still accepts every status the model itself declares" do
    leave = create(:leave_request)
    HrLite::LeaveRequest::STATUSES.each do |status|
      expect { leave.update_column(:status, status) }.not_to raise_error
    end

    run = create(:payroll_run)
    HrLite::PayrollRun::STATUSES.each do |status|
      expect { run.update_column(:status, status) }.not_to raise_error
    end
  end
end

RSpec.describe "Promotion rows point at an appraisal that exists" do
  it "nullifies the link when the appraisal is deleted underneath it" do
    profile = create(:employee_profile)
    appraisal = create(:appraisal, user: profile.user)
    change = HrLite::DesignationChange.create!(
      user: profile.user, to_designation: "Senior Consultant",
      effective_date: Date.current, appraisal_id: appraisal.id
    )

    # delete, not destroy: no callbacks, exactly what a raw cleanup does.
    HrLite::Appraisal.where(id: appraisal.id).delete_all

    expect(change.reload.appraisal_id).to be_nil
  end
end
