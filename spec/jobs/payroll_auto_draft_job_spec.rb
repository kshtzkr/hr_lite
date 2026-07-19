require "rails_helper"

RSpec.describe HrLite::PayrollAutoDraftJob do
  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  it "does nothing with no active employees" do
    expect { described_class.perform_now }.not_to change(HrLite::PayrollRun, :count)
  end

  it "creates + computes the previous month's run and emails leadership" do
    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)

    expect { described_class.perform_now }
      .to change(HrLite::PayrollRun, :count).by(1)
      .and have_enqueued_mail(HrLite::EventMailer, :leadership).once

    run = HrLite::PayrollRun.last
    expect(run.period_month).to eq(Date.current.prev_month.beginning_of_month)
    expect(run).to be_review
    expect(run.salary_slips.count).to eq(1)
  end

  it "is idempotent and never touches finalized/published runs" do
    profile = create(:employee_profile)
    create(:salary_structure, user: profile.user)
    leader = create(:user, email: "lead@x.test")

    described_class.perform_now
    expect { described_class.perform_now }.not_to change(HrLite::PayrollRun, :count)

    run = HrLite::PayrollRun.last
    run.finalize!(actor: leader)
    expect { described_class.perform_now }.not_to change { run.reload.status }
  end
end
