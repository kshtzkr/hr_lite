class AddRecheckedInAtToHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_attendance_records, :rechecked_in_at, :datetime
  end
end
