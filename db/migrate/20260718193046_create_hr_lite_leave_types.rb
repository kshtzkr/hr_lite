class CreateHrLiteLeaveTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_leave_types do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :color, null: false, default: "#0ea5e9"
      t.boolean :paid, null: false, default: true
      # nil quota = unlimited (LWP).
      t.decimal :annual_quota, precision: 4, scale: 1
      t.string :accrual, null: false, default: "yearly_upfront"
      t.decimal :carry_forward_cap, precision: 4, scale: 1, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :hr_lite_leave_types, :code, unique: true
    add_index :hr_lite_leave_types, :name, unique: true
  end
end
