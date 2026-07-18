class CreateHrLiteDesignationChanges < ActiveRecord::Migration[8.1]
  def change
    # Append-only career history.
    create_table :hr_lite_designation_changes do |t|
      t.bigint :user_id, null: false
      t.string :from_designation
      t.string :to_designation, null: false
      t.date :effective_date, null: false
      t.text :note
      t.bigint :appraisal_id
      t.bigint :created_by_id

      t.timestamps
    end
    add_index :hr_lite_designation_changes, [ :user_id, :effective_date ]
  end
end
