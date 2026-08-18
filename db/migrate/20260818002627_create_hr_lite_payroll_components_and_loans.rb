class CreateHrLitePayrollComponentsAndLoans < ActiveRecord::Migration[8.1]
  # Payroll knew exactly four earning heads — basic, HRA, special allowance,
  # "other" — because they were columns on the salary structure. A bonus, an
  # incentive, an LTA or a reimbursement had nowhere to go but "other", which
  # is one number on a payslip that should have said what it was for.
  #
  # Heads are DATA now. Amounts stay encrypted for the same reason every
  # amount in this engine is: a payslip line is somebody's pay.
  def change
    create_table :hr_lite_salary_components do |t|
      t.string :code, null: false
      t.string :label, null: false
      # earning | deduction
      t.string :kind, null: false, default: "earning"
      # Prorated by attendance like basic, or paid whole (a bonus is not
      # halved because somebody joined mid-month).
      t.boolean :prorated, null: false, default: true
      t.boolean :taxable, null: false, default: true
      # Counts toward the gross ESI is assessed on.
      t.boolean :counts_for_esi, null: false, default: true
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :hr_lite_salary_components, :code, unique: true
    add_check_constraint :hr_lite_salary_components, "kind IN ('earning', 'deduction')",
                         name: "hr_lite_salary_components_kind_check"

    # A one-off on a single month's payslip: a bonus, an incentive, an
    # arrears line after a backdated revision, a reimbursement. Dated to the
    # month rather than to the run, so it survives a run being deleted and
    # recomputed.
    create_table :hr_lite_payroll_line_items do |t|
      t.bigint :user_id, null: false
      t.date :period_month, null: false
      t.references :component, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_salary_components }
      t.text :amount, null: false # encrypted BigDecimal
      t.string :note
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :hr_lite_payroll_line_items, %i[user_id period_month]

    create_table :hr_lite_loans do |t|
      t.bigint :user_id, null: false
      t.text :principal, null: false      # encrypted
      t.text :monthly_instalment, null: false # encrypted
      t.date :starts_on, null: false
      t.string :reason
      # active | closed | cancelled
      t.string :status, null: false, default: "active"
      t.bigint :approved_by_id
      t.timestamps
    end
    add_index :hr_lite_loans, %i[user_id status]
    add_check_constraint :hr_lite_loans, "status IN ('active', 'closed', 'cancelled')",
                         name: "hr_lite_loans_status_check"

    # One row per month actually deducted. The outstanding balance is derived
    # from these rather than stored, so a recompute cannot double-count and a
    # deleted run cannot leave the balance wrong.
    create_table :hr_lite_loan_repayments do |t|
      t.references :loan, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_loans, on_delete: :cascade }
      t.date :period_month, null: false
      t.text :amount, null: false # encrypted
      t.timestamps
    end
    add_index :hr_lite_loan_repayments, %i[loan_id period_month], unique: true
  end
end
