class AddPermanentWfhToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :permanent_wfh, :boolean, null: false, default: false
  end
end
