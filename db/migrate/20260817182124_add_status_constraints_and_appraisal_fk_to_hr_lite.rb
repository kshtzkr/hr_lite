class AddStatusConstraintsAndAppraisalFkToHrLite < ActiveRecord::Migration[8.1]
  # Every status column in the engine is a plain string validated only in
  # Ruby, so anything that skips validations — update_column, update_all,
  # insert_all, a console fix, a future migration — can write a value no
  # screen renders and no transition accepts. These constraints put the
  # allowed set somewhere it cannot be bypassed.
  #
  # Deliberately in step with each model's own STATUSES array: adding a
  # status now means writing a migration, which is the point.
  STATUSES = {
    hr_lite_attendance_records: %w[present half_day],
    hr_lite_leave_requests: %w[pending approved rejected cancelled],
    hr_lite_comp_off_requests: %w[pending approved rejected cancelled],
    hr_lite_regularization_requests: %w[pending approved rejected cancelled],
    hr_lite_resignations: %w[pending accepted withdrawn],
    hr_lite_appraisals: %w[draft shared],
    hr_lite_payroll_runs: %w[draft processing review finalized published]
  }.freeze

  def up
    # On an install that already holds an off-list value the constraint build
    # fails with a bare integrity error naming neither the row nor the value.
    # Say what is actually in the way instead — this runs on live data.
    offenders = STATUSES.filter_map do |table, statuses|
      found = select_values(
        "SELECT DISTINCT status FROM #{table} WHERE status NOT IN (#{quoted(statuses)})"
      )
      "#{table}: #{found.join(', ')}" if found.any?
    end

    if offenders.any?
      raise ActiveRecord::IrreversibleMigration,
            "Cannot constrain status columns — these rows hold values no model " \
            "declares. Correct them first:\n  #{offenders.join("\n  ")}"
    end

    STATUSES.each do |table, statuses|
      add_check_constraint table, status_sql(statuses), name: constraint_name(table)
    end

    # has_one :designation_change, dependent: :nullify — with neither an index
    # nor a foreign key. Destroying an appraisal scanned the whole table to
    # find its promotion row, and nothing stopped that row from being left
    # pointing at an appraisal that no longer exists.
    add_index :hr_lite_designation_changes, :appraisal_id
    add_foreign_key :hr_lite_designation_changes, :hr_lite_appraisals,
                    column: :appraisal_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :hr_lite_designation_changes, column: :appraisal_id
    remove_index :hr_lite_designation_changes, :appraisal_id
    STATUSES.each_key { |table| remove_check_constraint table, name: constraint_name(table) }
  end

  private

  def status_sql(statuses) = "status IN (#{quoted(statuses)})"

  def quoted(statuses) = statuses.map { |s| connection.quote(s) }.join(", ")

  def constraint_name(table) = "#{table}_status_check"
end
