class CreateHrLiteLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_leave_requests do |t|
      t.bigint :user_id, null: false
      t.references :leave_type, null: false, foreign_key: { to_table: :hr_lite_leave_types }
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.boolean :half_day, null: false, default: false
      t.text :reason
      t.string :status, null: false, default: "pending"
      # Display cache; balance math always recomputes live.
      t.decimal :days_count, precision: 4, scale: 1, null: false
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_leave_requests, [ :user_id, :status ]
    add_index :hr_lite_leave_requests, [ :status, :start_date ]
    add_index :hr_lite_leave_requests, [ :start_date, :end_date ]
  end
end
