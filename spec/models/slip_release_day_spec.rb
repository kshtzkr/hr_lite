require "rails_helper"

RSpec.describe "config.slip_release_day" do
  let(:october) { Date.new(2027, 10, 1) }
  let(:ist) { Time.find_zone("Asia/Kolkata") }
  let(:bells) { [] }

  # October's run is published on 6 November, before a 10th-of-the-month release.
  around { |example| travel_to(ist.local(2027, 11, 6, 12)) { example.run } }

  before do
    HrLite.config.notify = ->(**kw) { bells << kw }
    HrLite.config.leadership_emails = [ "lead@x.test" ]
  end

  def slip_for(month, status: "published")
    slip = create(:salary_slip, payroll_run: create(:payroll_run, period_month: month))
    slip.payroll_run.update_columns(status: status) # rubocop:disable Rails/SkipsModelValidations
    slip
  end

  describe "assignment" do
    it "takes 1..28 or blank and rejects anything else at boot" do
      HrLite.config.slip_release_day = "10"
      expect(HrLite.config.slip_release_day).to eq(10)
      HrLite.config.slip_release_day = ""
      expect(HrLite.config.slip_release_day).to be_nil

      expect { HrLite.config.slip_release_day = 0 }.to raise_error(ArgumentError, /1\.\.28/)
      expect { HrLite.config.slip_release_day = 29 }.to raise_error(ArgumentError, /1\.\.28/)
      expect { HrLite.config.slip_release_day = "tenth" }.to raise_error(ArgumentError)
    end
  end

  describe "SalarySlip.released" do
    it "is every published slip when unset" do
      slip = slip_for(october)
      expect(HrLite::SalarySlip.released(on: Date.new(2027, 11, 1))).to contain_exactly(slip)
    end

    it "opens a month's slip on day N of the next month, not day N-1" do
      HrLite.config.slip_release_day = 10
      september = slip_for(Date.new(2027, 9, 1))
      oct = slip_for(october)
      slip_for(Date.new(2027, 8, 1), status: "finalized")

      expect(HrLite::SalarySlip.released(on: Date.new(2027, 11, 9))).to contain_exactly(september)
      expect(HrLite::SalarySlip.released(on: Date.new(2027, 11, 10))).to contain_exactly(september, oct)
    end
  end

  describe "PayrollRun#publish!" do
    def publish_october
      run = slip_for(october, status: "finalized").payroll_run
      run.publish!(actor: create(:user))
      run
    end

    it "tells leadership now and employees on the release day" do
      HrLite.config.slip_release_day = 10
      run = nil

      expect { run = publish_october }
        .to have_enqueued_job(HrLite::SlipsReadyJob).at(ist.local(2027, 11, 10))
        .and have_enqueued_mail(HrLite::EventMailer, :leadership).once
        .and have_enqueued_mail(HrLite::EventMailer, :event).exactly(0).times
      expect(bells).to be_empty

      expect { HrLite::SlipsReadyJob.perform_now(run) }
        .to have_enqueued_mail(HrLite::EventMailer, :event).once
        .and have_enqueued_mail(HrLite::EventMailer, :leadership).exactly(0).times
      expect(bells.map { |b| b[:user] }).to eq([ run.salary_slips.first.user ])
    end

    it "tells everyone at once when the release day has already passed" do
      HrLite.config.slip_release_day = 5

      expect { publish_october }
        .to have_enqueued_mail(HrLite::EventMailer, :event).once
        .and have_enqueued_job(HrLite::SlipsReadyJob).exactly(0).times
      expect(bells.size).to eq(1)
    end
  end
end
