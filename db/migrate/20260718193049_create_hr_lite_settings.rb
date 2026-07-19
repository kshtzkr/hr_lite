class CreateHrLiteSettings < ActiveRecord::Migration[8.1]
  def change
    # Singleton row — engine-owned settings (weekend policy for now).
    create_table :hr_lite_settings do |t|
      t.string :weekend_policy, null: false, default: "sat_sun"

      t.timestamps
    end
  end
end
