class AddCreatedByIdToHrLiteLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_leave_requests, :created_by_id, :integer, limit: 8
  end
end
