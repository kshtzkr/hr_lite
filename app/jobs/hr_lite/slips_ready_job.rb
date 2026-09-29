module HrLite
  # Tells employees their slip is ready on config.slip_release_day, when
  # SalarySlip.released first lets them open it. Enqueued by
  # PayrollRun#publish!, which already sent the leadership copy.
  class SlipsReadyJob < ApplicationJob
    def perform(run)
      run.notify_slips_ready(leadership: false)
    end
  end
end
