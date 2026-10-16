class CreateHrLitePenaltyRemovals < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_penalty_removals do |t|
      t.bigint :user_id, null: false
      t.integer :minutes, null: false
      t.text :reason, null: false
      t.bigint :removed_by_id, null: false

      t.timestamps
    end
    add_index :hr_lite_penalty_removals, :user_id
  end
end
