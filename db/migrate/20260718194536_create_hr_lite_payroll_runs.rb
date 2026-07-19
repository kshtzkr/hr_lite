class CreateHrLitePayrollRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_payroll_runs do |t|
      t.date :period_month, null: false
      t.string :status, null: false, default: "draft"
      t.json :warnings, null: false, default: []
      t.datetime :processed_at
      t.datetime :finalized_at
      t.datetime :published_at
      t.bigint :created_by_id
      t.bigint :finalized_by_id
      t.bigint :published_by_id
      t.text :notes

      t.timestamps
    end
    add_index :hr_lite_payroll_runs, :period_month, unique: true
    add_index :hr_lite_payroll_runs, :status
  end
end
