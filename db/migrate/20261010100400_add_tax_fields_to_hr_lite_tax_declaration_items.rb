class AddTaxFieldsToHrLiteTaxDeclarationItems < ActiveRecord::Migration[8.1]
  # senior lifts the 80D limit (₹25,000 → ₹50,000) for whoever the line covers;
  # landlord_pan is required once rent passes ₹1 lakh a year (encrypted:
  # it is somebody else's government ID). Proofs attach through Active Storage.
  def change
    add_column :hr_lite_tax_declaration_items, :senior, :boolean, null: false, default: false
    add_column :hr_lite_tax_declaration_items, :landlord_pan, :text
  end
end
