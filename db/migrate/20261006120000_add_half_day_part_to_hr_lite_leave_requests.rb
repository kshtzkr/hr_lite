class AddHalfDayPartToHrLiteLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_leave_requests, :half_day_part, :string
  end
end
