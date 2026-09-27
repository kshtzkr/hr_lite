class AddIdCardFieldsToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :blood_group, :text
    add_column :hr_lite_employee_profiles, :emergency_contact, :text
  end
end
