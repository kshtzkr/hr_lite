class CreateHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_attendance_records do |t|
      t.bigint :user_id, null: false
      t.date :date, null: false
      t.datetime :check_in_at
      t.datetime :check_out_at
      t.decimal :check_in_lat, precision: 9, scale: 6
      t.decimal :check_in_lng, precision: 9, scale: 6
      t.integer :check_in_accuracy_m
      t.decimal :check_out_lat, precision: 9, scale: 6
      t.decimal :check_out_lng, precision: 9, scale: 6
      t.integer :check_out_accuracy_m
      t.string :status, null: false, default: "present"
      t.boolean :flagged, null: false, default: false
      t.string :flag_note
      t.bigint :regularized_by_id
      t.datetime :regularized_at
      t.text :regularization_note

      t.timestamps
    end
    add_index :hr_lite_attendance_records, [ :user_id, :date ], unique: true
    add_index :hr_lite_attendance_records, :date
    add_index :hr_lite_attendance_records, [ :date, :flagged ]
  end
end
