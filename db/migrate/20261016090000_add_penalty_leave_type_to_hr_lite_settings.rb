class AddPenaltyLeaveTypeToHrLiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_settings, :penalty_leave_type_id, :bigint
  end
end
