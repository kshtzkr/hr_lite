class CreateHrLiteWfhRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_wfh_requests do |t|
      t.bigint :user_id, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_wfh_requests, [ :user_id, :start_date, :end_date ]
    add_index :hr_lite_wfh_requests, [ :status, :start_date ]
    add_check_constraint :hr_lite_wfh_requests, "status IN ('pending','approved','rejected','cancelled')",
                         name: "hr_lite_wfh_requests_status"
    add_check_constraint :hr_lite_wfh_requests, "end_date >= start_date", name: "hr_lite_wfh_requests_range"
  end
end
