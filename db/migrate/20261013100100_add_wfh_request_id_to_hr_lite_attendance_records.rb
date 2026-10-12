class AddWfhRequestIdToHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_attendance_records, :wfh_request_id, :bigint
    add_index :hr_lite_attendance_records, :wfh_request_id
  end
end
