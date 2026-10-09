class AddCtcToHrLiteSalaryStructures < ActiveRecord::Migration[8.1]
  # The agreed Annual CTC is now the input (encrypted, like every amount);
  # metro decides the HRA rate. Existing rows keep their lines and get a CTC
  # the next time they are saved.
  def change
    add_column :hr_lite_salary_structures, :annual_ctc, :text
    add_column :hr_lite_salary_structures, :metro, :boolean, null: false, default: false
  end
end
