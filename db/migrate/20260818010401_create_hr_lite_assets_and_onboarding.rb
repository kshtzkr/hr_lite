class CreateHrLiteAssetsAndOnboarding < ActiveRecord::Migration[8.1]
  # The two ends of employment that were still manual: the laptop somebody is
  # given on day one, and the checklist nobody remembers on their last.
  #
  # An asset that is never returned is a cost nobody notices, and access that
  # is never revoked is a security problem that outlives the employment.
  def change
    create_table :hr_lite_assets do |t|
      t.string :name, null: false
      # laptop | phone | sim | id_card | accessory | vehicle | other
      t.string :category, null: false, default: "other"
      t.string :serial_number
      t.date :purchased_on
      # available | assigned | returned | lost | damaged | retired
      t.string :status, null: false, default: "available"
      t.text :notes
      t.timestamps
    end
    add_index :hr_lite_assets, :status
    add_index :hr_lite_assets, :serial_number, unique: true,
              where: "serial_number IS NOT NULL"
    add_check_constraint :hr_lite_assets,
                         "status IN ('available', 'assigned', 'returned', 'lost', 'damaged', 'retired')",
                         name: "hr_lite_assets_status_check"

    # Append-only: who had it, when, and what state it came back in. Editing
    # an assignment away is how a missing laptop stops being anybody's.
    create_table :hr_lite_asset_assignments do |t|
      t.references :asset, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_assets, on_delete: :cascade }
      t.bigint :user_id, null: false
      t.date :assigned_on, null: false
      t.date :returned_on
      t.string :condition_note
      t.bigint :assigned_by_id
      t.timestamps
    end
    add_index :hr_lite_asset_assignments, %i[user_id returned_on]
    # One live holder at a time — two open assignments means the asset is in
    # two places, which it is not.
    add_index :hr_lite_asset_assignments, :asset_id,
              unique: true, where: "returned_on IS NULL",
              name: "index_hr_lite_asset_assignments_one_live_per_asset"

    create_table :hr_lite_checklist_templates do |t|
      # onboarding | offboarding
      t.string :kind, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      # Which permission the person who ticks it should hold — IT hands back
      # a laptop, HR collects a document, and neither should be the other.
      t.string :owner_permission
      # Days from the joining or leaving date this is due.
      t.integer :due_offset_days, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :hr_lite_checklist_templates, %i[kind position]
    add_check_constraint :hr_lite_checklist_templates, "kind IN ('onboarding', 'offboarding')",
                         name: "hr_lite_checklist_templates_kind_check"

    create_table :hr_lite_checklist_items do |t|
      t.bigint :user_id, null: false
      t.references :template, index: true,
                   foreign_key: { to_table: :hr_lite_checklist_templates, on_delete: :nullify }
      t.string :kind, null: false
      t.string :title, null: false
      t.date :due_on
      t.datetime :completed_at
      t.bigint :completed_by_id
      t.string :note
      t.timestamps
    end
    add_index :hr_lite_checklist_items, %i[user_id kind completed_at]
  end
end
