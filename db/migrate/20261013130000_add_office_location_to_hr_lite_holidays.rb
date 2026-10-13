class AddOfficeLocationToHrLiteHolidays < ActiveRecord::Migration[8.1]
  # A holiday is for every office (office_location_id null) or for one; two
  # offices may close on the same date for different reasons.
  def change
    add_column :hr_lite_holidays, :office_location_id, :bigint
    remove_index :hr_lite_holidays, :date, unique: true
    add_index :hr_lite_holidays, :date, unique: true, where: "office_location_id IS NULL",
              name: "index_hr_lite_holidays_all_offices"
    add_index :hr_lite_holidays, [ :date, :office_location_id ], unique: true,
              name: "index_hr_lite_holidays_per_office"
  end
end
