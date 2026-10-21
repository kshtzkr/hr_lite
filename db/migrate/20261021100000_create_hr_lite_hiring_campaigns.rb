class CreateHrLiteHiringCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_hiring_campaigns do |t|
      t.string :title, null: false
      t.string :position, null: false
      t.string :programme
      t.string :stipend
      t.string :ctc
      t.string :location
      t.string :schedule
      t.string :status, null: false, default: "open"
      t.timestamps
    end
  end
end
