class CreateHrLitePerformancePlans < ActiveRecord::Migration[8.1]
  # A performance improvement plan: goals with a deadline, closed as passed or
  # failed. Money tier, like appraisals — never deleted.
  def change
    create_table :hr_lite_performance_plans do |t|
      t.bigint :user_id, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.text :goals, null: false
      # active | extended | passed | failed
      t.string :status, null: false, default: "active"
      t.text :outcome_note
      t.datetime :closed_at
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :hr_lite_performance_plans, :user_id
    add_check_constraint :hr_lite_performance_plans,
                         "status IN ('active', 'extended', 'passed', 'failed')",
                         name: "hr_lite_performance_plans_status_check"
  end
end
