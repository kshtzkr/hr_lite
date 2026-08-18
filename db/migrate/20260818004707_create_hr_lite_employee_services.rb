class CreateHrLiteEmployeeServices < ActiveRecord::Migration[8.1]
  # Four things an employee has to leave the system to do today: claim an
  # expense, see what insurance they have, ask HR a question, and read the
  # policy they are being held to.
  #
  # Expenses and requests route through the approval engine from 0.9.0
  # rather than growing a fifth and sixth approve/reject of their own.
  def change
    create_table :hr_lite_expense_categories do |t|
      t.string :name, null: false
      t.text :monthly_cap        # encrypted; null = uncapped
      t.boolean :receipt_required, null: false, default: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :hr_lite_expense_categories, :name, unique: true

    create_table :hr_lite_expenses do |t|
      t.bigint :user_id, null: false
      t.references :category, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_expense_categories }
      t.text :amount, null: false # encrypted
      t.date :spent_on, null: false
      t.string :description, null: false
      # draft | submitted | approved | rejected | reimbursed | cancelled
      t.string :status, null: false, default: "draft"
      t.datetime :submitted_at
      t.string :decision_note
      # Which payroll month paid it out, once it was reimbursed.
      t.date :reimbursed_in
      t.timestamps
    end
    add_index :hr_lite_expenses, %i[user_id status]
    add_check_constraint :hr_lite_expenses,
                         "status IN ('draft', 'submitted', 'approved', 'rejected', 'reimbursed', 'cancelled')",
                         name: "hr_lite_expenses_status_check"

    create_table :hr_lite_benefits do |t|
      t.string :name, null: false
      # health | life | accident | other
      t.string :kind, null: false, default: "health"
      t.string :provider
      t.string :policy_number
      t.text :coverage          # encrypted — sum assured
      t.text :employer_premium  # encrypted
      t.text :employee_premium  # encrypted
      t.date :effective_from
      t.date :expires_on
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :hr_lite_benefit_enrolments do |t|
      t.references :benefit, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_benefits, on_delete: :cascade }
      t.bigint :user_id, null: false
      t.date :enrolled_on, null: false
      t.date :ended_on
      # Dependants covered, as a count — names and dates of birth are the
      # kind of family data this engine has no reason to hold.
      t.integer :dependants, null: false, default: 0
      t.timestamps
    end
    add_index :hr_lite_benefit_enrolments, %i[benefit_id user_id], unique: true

    create_table :hr_lite_hr_requests do |t|
      t.bigint :user_id, null: false
      # salary_certificate | address_change | bank_change | payroll_query | ...
      t.string :category, null: false
      t.string :subject, null: false
      t.text :body
      # open | in_progress | resolved | closed | cancelled
      t.string :status, null: false, default: "open"
      t.bigint :assigned_to_id
      t.datetime :resolved_at
      t.text :resolution
      t.timestamps
    end
    add_index :hr_lite_hr_requests, %i[user_id status]
    add_index :hr_lite_hr_requests, :assigned_to_id
    add_check_constraint :hr_lite_hr_requests,
                         "status IN ('open', 'in_progress', 'resolved', 'closed', 'cancelled')",
                         name: "hr_lite_hr_requests_status_check"

    create_table :hr_lite_policies do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.integer :version, null: false, default: 1
      t.date :effective_from, null: false
      t.boolean :acknowledgement_required, null: false, default: false
      t.boolean :published, null: false, default: false
      t.timestamps
    end
    add_index :hr_lite_policies, %i[title version], unique: true

    create_table :hr_lite_policy_acknowledgements do |t|
      t.references :policy, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_policies, on_delete: :cascade }
      t.bigint :user_id, null: false
      t.datetime :acknowledged_at, null: false
      t.timestamps
    end
    # One acknowledgement per person per VERSION: re-issuing a policy has to
    # ask everybody again, which is the entire point of versioning it.
    add_index :hr_lite_policy_acknowledgements, %i[policy_id user_id], unique: true
  end
end
