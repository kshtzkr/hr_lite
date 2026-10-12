class CreateHrLiteWorkLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_work_locations do |t|
      t.bigint :user_id, null: false
      t.string :name, null: false
      t.decimal :lat, precision: 9, scale: 6, null: false
      t.decimal :lng, precision: 9, scale: 6, null: false
      t.integer :accuracy_m, null: false
      t.string :address
      t.string :status, null: false, default: "pending"
      t.boolean :active, null: false, default: false
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_work_locations, [ :user_id, :status ]
    add_index :hr_lite_work_locations, :user_id, unique: true, where: "active", name: "index_hr_lite_work_locations_one_active"
    add_check_constraint :hr_lite_work_locations, "status IN ('pending','approved','rejected','removed')",
                         name: "hr_lite_work_locations_status"
  end
end
