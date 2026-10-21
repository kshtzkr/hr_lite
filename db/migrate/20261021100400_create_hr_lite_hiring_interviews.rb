class CreateHrLiteHiringInterviews < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_hiring_interviews do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :hr_lite_hiring_candidates }
      t.integer :round, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: "scheduled"
      t.string :event_id
      t.string :meet_link
      t.string :error
      t.timestamps
    end
    add_index :hr_lite_hiring_interviews, %i[candidate_id round]
  end
end
