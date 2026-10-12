class AddBreakMinutesToHrLiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_settings, :lunch_break_minutes, :integer, null: false, default: 30
    add_column :hr_lite_settings, :short_break_minutes, :integer, null: false, default: 10
  end
end
