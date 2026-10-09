class CreateHrLiteCaReviews < ActiveRecord::Migration[8.1]
  # The CA's year-end mark on one salary slip or tax declaration: verified,
  # or flagged with what is wrong until HR/payroll resolves it.
  def change
    create_table :hr_lite_ca_reviews do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      # verified | flagged | resolved
      t.string :status, null: false
      t.text :note
      t.bigint :reviewed_by_id, null: false
      t.datetime :reviewed_at, null: false
      t.bigint :resolved_by_id
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps
    end
    add_index :hr_lite_ca_reviews, %i[subject_type subject_id], unique: true
    add_check_constraint :hr_lite_ca_reviews, "status IN ('verified', 'flagged', 'resolved')", name: "hr_lite_ca_reviews_status_check"
  end
end
