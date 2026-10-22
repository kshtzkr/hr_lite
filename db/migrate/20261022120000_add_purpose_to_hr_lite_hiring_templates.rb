class AddPurposeToHrLiteHiringTemplates < ActiveRecord::Migration[8.1]
  # The email a decision button sends (selected / rejected / on_hold). One per
  # purpose; nil for ordinary templates.
  def change
    add_column :hr_lite_hiring_templates, :purpose, :string
    add_index :hr_lite_hiring_templates, :purpose, unique: true, where: "purpose IS NOT NULL"
  end
end
