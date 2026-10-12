class AddBufferToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_employee_profiles, :buffer_minutes, :integer
    add_column :hr_lite_employee_profiles, :buffer_reason, :string
    add_column :hr_lite_employee_profiles, :buffer_note, :text
  end
end
