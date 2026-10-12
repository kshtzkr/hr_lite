class CreateHrLiteAttendanceSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_attendance_slots do |t|
      t.bigint :user_id, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :period, null: false
      t.integer :start_minute, null: false
      t.boolean :locked, null: false, default: true
      t.bigint :set_by_id

      t.timestamps
    end
    add_index :hr_lite_attendance_slots, [ :user_id, :starts_on, :ends_on ]
  end
end
