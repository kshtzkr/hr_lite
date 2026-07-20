class AddEmployeeCodePrefixToHrLiteSettings < ActiveRecord::Migration[8.0]
  def change
    # Employee codes are system-assigned: prefix + zero-padded sequence
    # (EMP001, EMP002, ...). Leadership edits the prefix under Settings.
    add_column :hr_lite_settings, :employee_code_prefix, :string, null: false, default: "EMP"
  end
end
