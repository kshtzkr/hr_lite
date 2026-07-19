class AddCompOffToHrLiteLeaveTypes < ActiveRecord::Migration[8.0]
  def change
    # Marks which leave type approved comp-off requests credit into.
    add_column :hr_lite_leave_types, :comp_off, :boolean, null: false, default: false
  end
end
