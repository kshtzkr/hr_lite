module HrLite
  # Idempotent reference data. Hosts run it on every deploy
  # (`rake hr_lite:seed`); re-runs never overwrite operator edits.
  # The leave/holiday phase adds the actual seeders; run! stays the single
  # entry point.
  module Seeds
    def self.run!
      results = []
      results.concat(seed_leave_types!) if respond_to?(:seed_leave_types!)
      results.concat(seed_holidays!) if respond_to?(:seed_holidays!)
      results
    end
  end
end
