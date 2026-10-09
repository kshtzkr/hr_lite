class CreateHrLiteAwards < ActiveRecord::Migration[8.1]
  # Employee of the month, quarter and year: one winner per period.
  def change
    create_table :hr_lite_awards do |t|
      t.bigint :user_id, null: false
      # month | quarter | year
      t.string :kind, null: false
      t.date :period_start, null: false
      t.text :citation, null: false
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :hr_lite_awards, %i[kind period_start], unique: true
    add_index :hr_lite_awards, :user_id
    add_check_constraint :hr_lite_awards, "kind IN ('month', 'quarter', 'year')", name: "hr_lite_awards_kind_check"
  end
end
