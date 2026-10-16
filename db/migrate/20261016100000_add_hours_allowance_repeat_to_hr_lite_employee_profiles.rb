class AddHoursAllowanceRepeatToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :hours_allowance_repeat, :string
  end
end
