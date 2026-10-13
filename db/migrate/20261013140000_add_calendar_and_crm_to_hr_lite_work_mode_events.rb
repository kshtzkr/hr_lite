class AddCalendarAndCrmToHrLiteWorkModeEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :hr_lite_work_mode_events, :calendar_event_id, :string
    add_column :hr_lite_work_mode_events, :crm_ref, :string
    # A calendar meeting opens at most once per person, however often we sync.
    add_index :hr_lite_work_mode_events, [ :user_id, :calendar_event_id ], unique: true,
              where: "calendar_event_id IS NOT NULL", name: "index_hr_lite_work_mode_events_one_per_calendar_event"
  end
end
