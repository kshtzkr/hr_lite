class CreateHrLiteApprovals < ActiveRecord::Migration[8.1]
  # Leave, comp-off, regularization and resignation each grew their own
  # approve/reject/cancel, with their own transition guard and their own
  # notification. Four copies of one idea, and every module still to come
  # (expenses, loans, salary revisions, document verification) would have
  # been a fifth.
  #
  # A FLOW is the definition — "leave needs the manager, then HR". A STEP is
  # one rung of it, naming an approver by RULE rather than by person, so the
  # flow survives somebody leaving. An APPROVAL is one live decision on one
  # record.
  def change
    create_table :hr_lite_approval_flows do |t|
      # The model this flow decides on, e.g. "HrLite::LeaveRequest".
      t.string :subject_type, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :hr_lite_approval_flows, :subject_type,
              unique: true, where: "active", name: "index_hr_lite_approval_flows_one_active_per_type"

    create_table :hr_lite_approval_steps do |t|
      t.references :flow, null: false, index: false,
                   foreign_key: { to_table: :hr_lite_approval_flows, on_delete: :cascade }
      t.integer :position, null: false
      # manager | manager_of_manager | permission | user
      t.string :approver_rule, null: false
      # permission key for `permission`, user id for `user`, unused otherwise
      t.string :approver_key
      # Everybody on this rung must decide, rather than the first to answer.
      t.boolean :unanimous, null: false, default: false
      # Hours before the step is escalated. Null = never.
      t.integer :sla_hours
      t.timestamps
    end
    add_index :hr_lite_approval_steps, %i[flow_id position], unique: true
    add_check_constraint :hr_lite_approval_steps,
                         "approver_rule IN ('manager', 'manager_of_manager', 'permission', 'user')",
                         name: "hr_lite_approval_steps_rule_check"

    create_table :hr_lite_approvals do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.references :step, null: false, index: false,
                   foreign_key: { to_table: :hr_lite_approval_steps, on_delete: :cascade }
      t.integer :position, null: false
      t.bigint :approver_id, null: false
      # pending | approved | rejected | returned | skipped | cancelled
      t.string :status, null: false, default: "pending"
      t.text :note
      t.datetime :decided_at
      # Who decided in the approver's place, when they had delegated.
      t.bigint :decided_by_id
      t.datetime :escalated_at
      t.timestamps
    end
    add_index :hr_lite_approvals, %i[subject_type subject_id position]
    # One live row per approver per rung: two would let the same person
    # decide twice, or a retry double-count a unanimous step.
    add_index :hr_lite_approvals, %i[subject_type subject_id position approver_id],
              unique: true, name: "index_hr_lite_approvals_one_per_approver_per_step"
    add_index :hr_lite_approvals, :approver_id
    add_check_constraint :hr_lite_approvals,
                         "status IN ('pending', 'approved', 'rejected', 'returned', 'skipped', 'cancelled')",
                         name: "hr_lite_approvals_status_check"

    create_table :hr_lite_approval_delegations do |t|
      t.bigint :from_user_id, null: false
      t.bigint :to_user_id, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :reason
      t.timestamps
    end
    add_index :hr_lite_approval_delegations, %i[from_user_id starts_on ends_on],
              name: "index_hr_lite_delegations_on_from_and_dates"
  end
end
