class AddPunchPlacesToHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_attendance_records, :check_in_place, :string
    add_column :hr_lite_attendance_records, :check_out_place, :string
    add_column :hr_lite_attendance_records, :check_out_work_location_id, :bigint
    add_column :hr_lite_attendance_records, :check_in_home_m, :integer
    add_column :hr_lite_attendance_records, :check_out_home_m, :integer
    add_index :hr_lite_attendance_records, :check_out_work_location_id
  end
end
