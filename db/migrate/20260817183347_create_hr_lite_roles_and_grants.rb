class CreateHrLiteRolesAndGrants < ActiveRecord::Migration[8.1]
  # Roles replace the three configured lambdas (admin_check, leadership_emails,
  # superadmin_emails). Two of those matched a MUTABLE email string — a
  # permission stored in a column the host lets people edit.
  #
  # Permissions themselves are not a table: the vocabulary is declared in
  # HrLite::Permissions::REGISTRY, so a grant is a (role, key, scope) row and
  # an unknown key cannot be stored. That keeps seeding idempotent, and makes
  # retiring a permission a code change with a spec rather than silent data.
  def change
    create_table :hr_lite_roles do |t|
      t.string :name, null: false
      t.string :description
      # Roles the engine seeds and refers to by name. Renaming or deleting one
      # is refused by the model — the upgrade path off the email lists lands
      # people in these, and the roles screen has to keep meaning something.
      t.boolean :system, null: false, default: false
      t.timestamps
    end
    add_index :hr_lite_roles, :name, unique: true

    create_table :hr_lite_role_grants do |t|
      t.references :role, null: false, index: false,
                   foreign_key: { to_table: :hr_lite_roles, on_delete: :cascade }
      t.string :permission_key, null: false
      # self | team | all — see HrLite::Permissions. Stored per grant so one
      # key covers "own leave", "my reports' leave" and "everyone's leave".
      t.string :scope, null: false, default: "self"
      t.timestamps
    end
    # One scope per (role, permission): a role either reaches a set of rows or
    # it does not, and two rows for one key would make that a lookup race.
    add_index :hr_lite_role_grants, %i[role_id permission_key], unique: true
    add_check_constraint :hr_lite_role_grants, "scope IN ('self', 'team', 'all')",
                         name: "hr_lite_role_grants_scope_check"

    create_table :hr_lite_role_assignments do |t|
      # No FK to the host user table — its name is host-specific, the same
      # reason every other user_id in this engine is a bare bigint.
      t.bigint :user_id, null: false
      t.references :role, null: false, index: false,
                   foreign_key: { to_table: :hr_lite_roles, on_delete: :cascade }
      t.bigint :granted_by_id
      t.timestamps
    end
    add_index :hr_lite_role_assignments, %i[user_id role_id], unique: true
    add_index :hr_lite_role_assignments, :role_id
  end
end
