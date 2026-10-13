class AddFieldStaffToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :field_staff, :boolean, null: false, default: false
  end
end
