class AddHoursAllowanceToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :hours_allowance_minutes, :integer
    add_column :hr_lite_employee_profiles, :hours_allowance_reason, :text
  end
end
