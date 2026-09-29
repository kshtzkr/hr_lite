class AddPaidDaysToHrLiteLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_leave_requests, :paid_days, :decimal, precision: 4, scale: 1
  end
end
