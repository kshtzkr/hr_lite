class CreateHrLiteResignations < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_resignations do |t|
      t.bigint :user_id, null: false
      t.text :reason
      t.date :proposed_last_day, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end
    add_index :hr_lite_resignations, [ :user_id, :status ]
  end
end
