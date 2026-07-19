class CreateHrLiteKudos < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_kudos do |t|
      # No FK to the host user table — its name is host-specific.
      t.bigint :giver_id, null: false
      t.string :badge
      t.text :message, null: false

      t.timestamps
    end
    add_index :hr_lite_kudos, :giver_id
    add_index :hr_lite_kudos, :created_at
  end
end
