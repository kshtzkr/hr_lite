class CreateHrLiteWorkModeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_work_mode_events do |t|
      t.bigint :user_id, null: false
      t.string :mode, null: false
      t.string :layer, null: false
      t.string :source, null: false
      t.datetime :started_at, null: false
      t.datetime :ends_at
      t.datetime :ended_at
      t.string :end_reason
      t.boolean :overrun, null: false, default: false
      t.bigint :attendance_record_id
      t.bigint :wfh_request_id
      t.bigint :work_location_id
      t.bigint :set_by_id
      t.string :title
      t.string :client
      t.string :destination
      t.text :reason

      t.timestamps
    end
    add_index :hr_lite_work_mode_events, [ :user_id, :started_at ]
    add_index :hr_lite_work_mode_events, [ :user_id, :layer ], unique: true, where: "ended_at IS NULL",
              name: "index_hr_lite_work_mode_events_one_open"
    add_check_constraint :hr_lite_work_mode_events, "source IN ('system','employee','hr')", name: "hr_lite_work_mode_events_source"
    add_check_constraint :hr_lite_work_mode_events, "layer IN ('primary','overlay')", name: "hr_lite_work_mode_events_layer"
  end
end
