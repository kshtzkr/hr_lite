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
end
