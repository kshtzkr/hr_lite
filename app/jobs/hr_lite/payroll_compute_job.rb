module HrLite
  # Compute off the request (PayrollRun#compute_later!). A failure restores
  # the run's status and lands as a run warning instead of a 500.
  class PayrollComputeJob < ApplicationJob
    def perform(run, from, actor)
      run.compute!(actor: actor, from: from)
    rescue => e
      Rails.error.report(e)
      run.reload.update_columns(warnings: run.warnings | [ "Compute failed (#{e.message.truncate(150)}) — nothing changed; try again." ]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
