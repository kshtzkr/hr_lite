class AddWorkModeToHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_attendance_records, :work_mode, :string
    add_column :hr_lite_attendance_records, :work_location_id, :bigint
    remove_column :hr_lite_attendance_records, :wfh, :boolean, null: false, default: false
  end
end
