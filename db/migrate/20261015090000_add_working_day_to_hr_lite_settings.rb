class AddWorkingDayToHrLiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_settings, :day_minutes, :integer, null: false, default: 510
    add_column :hr_lite_settings, :half_day_below_minutes, :integer, null: false, default: 255
    add_column :hr_lite_settings, :recheck_in_from, :string, null: false, default: "09:00"
    add_column :hr_lite_settings, :recheck_in_until, :string, null: false, default: "20:00"
  end
end
