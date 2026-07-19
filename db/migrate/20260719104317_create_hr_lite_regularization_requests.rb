class CreateHrLiteRegularizationRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :hr_lite_regularization_requests do |t|
      t.bigint :user_id, null: false
      t.date :date, null: false
      t.datetime :check_in_at
      t.datetime :check_out_at
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_regularization_requests, [ :user_id, :status ]
    add_index :hr_lite_regularization_requests, [ :user_id, :date ]
    add_index :hr_lite_regularization_requests, [ :status, :date ]
  end
end
