class CreateHrLiteHiringReplies < ActiveRecord::Migration[8.1]
  # One reply link per candidate per interview round: their answers, the day
  # and 2-hour slot they picked, an optional alternate phone, and (from round
  # 2) their documents through Active Storage, stored encrypted. Round 3 adds
  # the joining KYC: Aadhaar, PAN (or "PAN pending") and salary slips.
  def change
    create_table :hr_lite_hiring_replies do |t|
      t.references :candidate, null: false, foreign_key: { to_table: :hr_lite_hiring_candidates }
      t.integer :round, null: false
      t.string :token, null: false
      t.json :answers, null: false, default: {}
      t.text :alternate_phone
      t.text :aadhaar_number
      t.text :pan_number
      t.boolean :pan_pending, null: false, default: false
      t.boolean :no_salary_slips, null: false, default: false
      t.date :preferred_date
      t.string :preferred_slot
      t.datetime :responded_at
      t.timestamps
    end
    add_index :hr_lite_hiring_replies, :token, unique: true
    add_index :hr_lite_hiring_replies, %i[candidate_id round], unique: true
    add_index :hr_lite_hiring_replies, %i[preferred_date preferred_slot]
  end
end
