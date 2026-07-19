class CreateHrLiteLeaveBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_leave_balances do |t|
      t.bigint :user_id, null: false
      t.references :leave_type, null: false, foreign_key: { to_table: :hr_lite_leave_types }
      t.integer :year, null: false
      # Only carry-in and manual adjustments are materialized; entitlement
      # and usage are computed live so they self-heal.
      t.decimal :carried_forward, precision: 4, scale: 1, null: false, default: 0
      t.decimal :adjustment, precision: 5, scale: 1, null: false, default: 0
      t.string :adjustment_note

      t.timestamps
    end
    add_index :hr_lite_leave_balances, [ :user_id, :leave_type_id, :year ], unique: true
  end
end
