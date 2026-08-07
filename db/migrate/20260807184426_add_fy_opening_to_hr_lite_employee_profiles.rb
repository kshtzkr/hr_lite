class AddFyOpeningToHrLiteEmployeeProfiles < ActiveRecord::Migration[8.0]
  # Income already paid this financial year that this install did not run:
  # a previous employer, or the months before payroll was switched on. TDS
  # projects the annual total from slips it can see, so without these the
  # first year after a mid-year start under-projects — often far enough
  # under the rebate cap to deduct nothing at all.
  #
  # Text, because they are encrypted at rest like every other money column
  # (see HrLite::EncryptedMoney).
  def change
    add_column :hr_lite_employee_profiles, :fy_opening_gross, :text
    add_column :hr_lite_employee_profiles, :fy_opening_tds, :text
  end
end
