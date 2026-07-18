class CreateHrLiteSalaryStructures < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_salary_structures do |t|
      t.bigint :user_id, null: false
      # Always the 1st of a month — revisions take effect from the 1st only.
      t.date :effective_from, null: false
      # Encrypted money (text columns, BigDecimal via EncryptedMoney):
      t.text :basic
      t.text :hra
      t.text :special_allowance
      t.text :other_earnings
      t.boolean :pf_applicable, null: false, default: true
      t.boolean :pf_on_full_basic, null: false, default: false
      t.boolean :esi_applicable, null: false, default: true
      t.string :pt_state, null: false, default: "none"
      t.text :notes
      t.bigint :created_by_id

      t.timestamps
    end
    add_index :hr_lite_salary_structures, [ :user_id, :effective_from ], unique: true
  end
end
