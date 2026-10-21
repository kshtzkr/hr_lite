class CreateHrLiteHiringCandidates < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_hiring_candidates do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :hr_lite_hiring_campaigns }
      t.string :name, null: false
      t.string :email, null: false
      t.text :phone
      t.text :date_of_birth
      t.string :campus
      t.string :course
      t.string :branch
      t.string :cv_url
      t.json :extra, null: false, default: {}
      t.string :stage, null: false, default: "imported"
      t.integer :round, null: false, default: 0
      t.string :rejection_reason
      t.timestamps
    end
    add_index :hr_lite_hiring_candidates, %i[campaign_id email], unique: true
    add_index :hr_lite_hiring_candidates, %i[campaign_id stage]
  end
end
