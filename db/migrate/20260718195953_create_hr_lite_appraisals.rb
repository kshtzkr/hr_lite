class CreateHrLiteAppraisals < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_appraisals do |t|
      t.bigint :user_id, null: false
      t.bigint :reviewer_id, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.integer :rating
      t.text :strengths
      t.text :improvements
      t.string :outcome, null: false, default: "none"
      t.date :effective_date
      t.string :new_designation
      t.string :status, null: false, default: "draft"
      t.datetime :shared_at

      t.timestamps
    end
    add_index :hr_lite_appraisals, [ :user_id, :period_end ]
    add_index :hr_lite_appraisals, :status
  end
end
