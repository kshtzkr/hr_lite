class AddAllowSundayToHrLiteHiringCampaigns < ActiveRecord::Migration[8.1]
  # Sunday is off; HR can open it for one campaign's interview slots.
  def change
    add_column :hr_lite_hiring_campaigns, :allow_sunday, :boolean, null: false, default: false
  end
end
