# Dummy-app-only tables. Engine tables come from the engine's own
# migrations, run by spec/rails_helper.rb at boot.
ActiveRecord::Schema[8.1].define(version: 1) do
  create_table :users, force: :cascade do |t|
    t.string :name
    t.string :email, null: false
    t.boolean :admin, null: false, default: false
    t.string :designation
    t.timestamps
  end
  add_index :users, :email, unique: true

  # Active Storage, as a real host would have after `active_storage:install`.
  # Employee documents attach through it, so the suite needs the tables to
  # exercise anything more than the metadata.
  create_table :active_storage_blobs, force: :cascade do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
  end
  add_index :active_storage_blobs, :key, unique: true

  create_table :active_storage_attachments, force: :cascade do |t|
    t.string :name, null: false
    t.string :record_type, null: false
    t.bigint :record_id, null: false
    t.bigint :blob_id, null: false
    t.datetime :created_at, null: false
  end
  add_index :active_storage_attachments, %i[record_type record_id name blob_id],
            name: "index_active_storage_attachments_uniqueness", unique: true

  create_table :active_storage_variant_records, force: :cascade do |t|
    t.bigint :blob_id, null: false
    t.string :variation_digest, null: false
  end
  add_index :active_storage_variant_records, %i[blob_id variation_digest],
            name: "index_active_storage_variant_records_uniqueness", unique: true
end
