class CreateHrLiteAttendancePenalties < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_attendance_penalties do |t|
      t.bigint :user_id, null: false
      t.date :date, null: false
      t.integer :minutes, null: false
      t.string :reason, null: false
      t.bigint :attendance_record_id, null: false
      t.datetime :removed_at
      t.bigint :removed_by_id
      t.text :removal_reason

      t.timestamps
    end
    add_index :hr_lite_attendance_penalties, [ :user_id, :date ]
    add_index :hr_lite_attendance_penalties, [ :attendance_record_id, :reason, :date ], unique: true,
              name: "index_hr_lite_attendance_penalties_once"
  end
end
