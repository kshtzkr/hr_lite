class CreateHrLiteHiringMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_hiring_messages do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :hr_lite_hiring_candidates }
      t.references :template, null: false, foreign_key: { to_table: :hr_lite_hiring_templates }
      t.string :batch, null: false
      t.string :status, null: false, default: "queued"
      t.string :gmail_message_id
      t.string :gmail_thread_id
      t.string :error
      t.datetime :sent_at
      t.bigint :sent_by_id
      t.timestamps
    end
    # One send of a template per candidate: double clicks and job redelivery cannot repeat it.
    add_index :hr_lite_hiring_messages, %i[candidate_id template_id], unique: true
    add_index :hr_lite_hiring_messages, :batch
  end
end
