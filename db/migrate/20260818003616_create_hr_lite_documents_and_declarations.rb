class CreateHrLiteDocumentsAndDeclarations < ActiveRecord::Migration[8.1]
  # Two gaps that were table stakes and simply absent: nowhere to keep an
  # employee's documents, and a tax declaration that was ONE opaque number.
  #
  # `declared_annual_deductions` on the profile is a single figure an admin
  # types in. Nobody can see what it is made of, the employee cannot submit
  # their own, and there is nowhere to put the proof. That is the number the
  # whole year's TDS is projected from.
  def change
    create_table :hr_lite_documents do |t|
      t.bigint :user_id, null: false
      # aadhaar | pan | passport | bank | offer_letter | ... — data, so an
      # install can add its own without a release.
      t.string :category, null: false
      t.string :title, null: false
      t.string :reference_number
      t.date :issued_on
      t.date :expires_on
      # self | hr | money — who may open the file. A payslip and a passport
      # are not the same kind of secret.
      #
      # No column default on purpose: the model derives one from the category
      # when none was chosen, and a column default would make "unset" and
      # "deliberately hr" indistinguishable.
      t.string :visibility, null: false
      # pending | verified | rejected
      t.string :verification, null: false, default: "pending"
      t.bigint :verified_by_id
      t.datetime :verified_at
      t.string :verification_note
      t.bigint :uploaded_by_id
      t.timestamps
    end
    add_index :hr_lite_documents, %i[user_id category]
    add_index :hr_lite_documents, :expires_on
    add_check_constraint :hr_lite_documents, "visibility IN ('self', 'hr', 'money')",
                         name: "hr_lite_documents_visibility_check"
    add_check_constraint :hr_lite_documents,
                         "verification IN ('pending', 'verified', 'rejected')",
                         name: "hr_lite_documents_verification_check"

    create_table :hr_lite_tax_declarations do |t|
      t.bigint :user_id, null: false
      # 1 April of the financial year it covers.
      t.date :financial_year, null: false
      t.string :regime, null: false, default: "new"
      # draft | submitted | verified | rejected
      t.string :status, null: false, default: "draft"
      t.datetime :submitted_at
      t.bigint :verified_by_id
      t.datetime :verified_at
      t.string :note
      t.timestamps
    end
    add_index :hr_lite_tax_declarations, %i[user_id financial_year], unique: true
    add_check_constraint :hr_lite_tax_declarations,
                         "status IN ('draft', 'submitted', 'verified', 'rejected')",
                         name: "hr_lite_tax_declarations_status_check"

    create_table :hr_lite_tax_declaration_items do |t|
      t.references :declaration, null: false, index: true,
                   foreign_key: { to_table: :hr_lite_tax_declarations, on_delete: :cascade }
      # 80c | 80d | hra | 80ccd_1b | 24b | other
      t.string :section, null: false
      t.string :label
      t.text :declared_amount, null: false # encrypted
      # What proof actually supported, once HR has looked. Null until then.
      t.text :verified_amount
      t.timestamps
    end
    add_index :hr_lite_tax_declaration_items, %i[declaration_id section]
  end
end
