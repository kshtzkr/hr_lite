class CreateHrLiteOfficeLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_office_locations do |t|
      t.string :name, null: false
      t.decimal :lat, precision: 9, scale: 6, null: false
      t.decimal :lng, precision: 9, scale: 6, null: false
      t.integer :radius_m, null: false, default: 200
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
