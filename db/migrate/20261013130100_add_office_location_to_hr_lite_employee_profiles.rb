class AddOfficeLocationToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :office_location_id, :bigint
    add_index :hr_lite_employee_profiles, :office_location_id
  end
end
