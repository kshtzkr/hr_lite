class CreateHrLiteHolidays < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_holidays do |t|
      t.date :date, null: false
      t.string :name, null: false
      # Optional/restricted holidays render on the calendar but do NOT
      # count as working-day exclusions.
      t.boolean :optional, null: false, default: false

      t.timestamps
    end
    add_index :hr_lite_holidays, :date, unique: true
  end
end
