class CreateHrLiteAttendancePunches < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_attendance_punches do |t|
      t.bigint :user_id, null: false
      t.date :date, null: false
      t.bigint :attendance_record_id
      t.string :kind, null: false
      t.datetime :at, null: false
      t.decimal :lat, precision: 9, scale: 6
      t.decimal :lng, precision: 9, scale: 6
      t.integer :accuracy_m
      t.string :place
      t.integer :home_m
      t.bigint :work_location_id

      t.timestamps
    end
    add_index :hr_lite_attendance_punches, [ :user_id, :date ]
  end
end
