class CreateHrLiteKudoMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_kudo_mentions do |t|
      t.references :kudo, null: false, foreign_key: { to_table: :hr_lite_kudos, on_delete: :cascade }
      t.bigint :user_id, null: false

      t.timestamps
    end
    add_index :hr_lite_kudo_mentions, [ :kudo_id, :user_id ], unique: true
    add_index :hr_lite_kudo_mentions, :user_id
  end
end
