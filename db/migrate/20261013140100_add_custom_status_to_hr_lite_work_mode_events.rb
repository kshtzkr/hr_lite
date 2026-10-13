class AddCustomStatusToHrLiteWorkModeEvents < ActiveRecord::Migration[8.1]
  # A third layer: a person's own status ("In Goa till Friday" + an emoji),
  # alongside their work mode and any break or meeting.
  def change
    add_column :hr_lite_work_mode_events, :emoji, :string
    remove_check_constraint :hr_lite_work_mode_events, "layer IN ('primary','overlay')", name: "hr_lite_work_mode_events_layer"
    add_check_constraint :hr_lite_work_mode_events, "layer IN ('primary','overlay','status')", name: "hr_lite_work_mode_events_layer"
  end
end
