class AddManagerToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.0]
  def change
    # Reporting line: the user this employee reports to (L1). The chain
    # upward gives L2, L3, ... and powers the everyone-visible org chart.
    add_column :hr_lite_employee_profiles, :manager_id, :bigint
    add_index :hr_lite_employee_profiles, :manager_id
  end
end
