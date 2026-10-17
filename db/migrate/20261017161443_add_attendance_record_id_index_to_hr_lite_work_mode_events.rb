class AddAttendanceRecordIdIndexToHrLiteWorkModeEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :hr_lite_work_mode_events, :attendance_record_id, if_not_exists: true
  end
end
