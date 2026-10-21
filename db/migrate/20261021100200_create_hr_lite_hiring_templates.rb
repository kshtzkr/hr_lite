class CreateHrLiteHiringTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :hr_lite_hiring_templates do |t|
      t.string :name, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.timestamps
    end
  end
end
