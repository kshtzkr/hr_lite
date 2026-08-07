class AddOutOfWindowDaysToHrLiteSalarySlips < ActiveRecord::Migration[8.0]
  # Days outside the employment window — before joining, after the last day.
  # SlipBuilder already subtracts them from payable days, but never recorded
  # them, so a mid-month joiner's payslip read "15 payable, 0 LOP" of a
  # 30-day month and looked as though days had gone missing.
  #
  # Not encrypted: a day count is not money.
  def change
    add_column :hr_lite_salary_slips, :out_of_window_days, :decimal, precision: 4, scale: 1,
                                                                     default: "0.0", null: false
  end
end
