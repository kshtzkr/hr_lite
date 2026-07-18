class CreateHrLiteEmployeeProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_employee_profiles do |t|
      t.bigint :user_id, null: false
      t.string :employee_code, null: false
      t.string :designation
      t.date :date_of_birth
      t.date :date_of_joining, null: false
      t.date :date_of_exit
      t.string :department
      t.string :work_location
      # Encrypted (Rails AR encryption — text columns):
      t.text :pan_number
      t.text :pf_uan
      t.text :esi_number
      t.text :bank_account_number
      t.text :bank_ifsc
      t.text :declared_annual_deductions
      t.string :bank_name
      t.string :tax_regime, null: false, default: "new"

      t.timestamps
    end
    add_index :hr_lite_employee_profiles, :user_id, unique: true
    add_index :hr_lite_employee_profiles, :employee_code, unique: true
  end
end
