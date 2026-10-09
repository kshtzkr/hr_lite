class AddApprovalToHrLitePayrollRuns < ActiveRecord::Migration[8.1]
  # Two people approve a run: the first is stamped here, the second
  # finalizes and publishes it. auto_approved_at marks a run the 3rd-of-month
  # job approved because nobody had.
  def change
    add_column :hr_lite_payroll_runs, :first_approved_by_id, :bigint
    add_column :hr_lite_payroll_runs, :first_approved_at, :datetime
    add_column :hr_lite_payroll_runs, :auto_approved_at, :datetime
  end
end
