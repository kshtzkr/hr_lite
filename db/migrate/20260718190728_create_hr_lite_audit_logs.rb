class CreateHrLiteAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_audit_logs do |t|
      t.bigint :actor_id
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.json :audited_changes, null: false, default: {}

      t.datetime :created_at, null: false
    end
    add_index :hr_lite_audit_logs, [ :subject_type, :subject_id ]
    add_index :hr_lite_audit_logs, :created_at
  end
end
