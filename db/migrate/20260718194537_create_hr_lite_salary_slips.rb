class CreateHrLiteSalarySlips < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_salary_slips do |t|
      t.references :payroll_run, null: false,
                   foreign_key: { to_table: :hr_lite_payroll_runs, on_delete: :cascade }
      t.bigint :user_id, null: false
      t.date :period_month, null: false
      t.integer :days_in_month, null: false
      t.decimal :payable_days, precision: 5, scale: 2, null: false
      t.decimal :lop_days, precision: 5, scale: 2, null: false, default: 0
      t.decimal :lop_override, precision: 5, scale: 2
      # Encrypted money / encrypted JSON (text columns):
      t.text :tds_override
      t.text :earnings
      t.text :deductions
      t.text :employer_costs
      t.text :tax_details
      t.text :gross_earnings
      t.text :total_deductions
      t.text :net_pay
      t.datetime :computed_at

      t.timestamps
    end
    add_index :hr_lite_salary_slips, [ :payroll_run_id, :user_id ], unique: true
    add_index :hr_lite_salary_slips, [ :user_id, :period_month ], unique: true
  end
end
