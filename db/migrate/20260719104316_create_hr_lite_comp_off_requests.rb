class CreateHrLiteCompOffRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :hr_lite_comp_off_requests do |t|
      t.bigint :user_id, null: false
      t.date :date_worked, null: false
      t.boolean :half_day, null: false, default: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_comp_off_requests, [ :user_id, :status ]
    add_index :hr_lite_comp_off_requests, [ :user_id, :date_worked ]
    add_index :hr_lite_comp_off_requests, [ :status, :date_worked ]
    # Two tabs / a double-tap racing past the app-level duplicate check
    # must not create two live requests for one worked day.
    add_index :hr_lite_comp_off_requests, [ :user_id, :date_worked ],
              unique: true, where: "status IN ('pending', 'approved')",
              name: "index_hr_lite_comp_off_requests_live_uniqueness"
  end
end
