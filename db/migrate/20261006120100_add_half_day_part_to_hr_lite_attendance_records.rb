class AddHalfDayPartToHrLiteAttendanceRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_attendance_records, :half_day_part, :string
  end
end
