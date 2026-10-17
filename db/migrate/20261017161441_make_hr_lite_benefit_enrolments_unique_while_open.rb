class MakeHrLiteBenefitEnrolmentsUniqueWhileOpen < ActiveRecord::Migration[8.1]
  # One open enrolment per person per plan; ended ones stay as history.
  def change
    remove_index :hr_lite_benefit_enrolments, %i[benefit_id user_id], unique: true, if_exists: true
    add_index :hr_lite_benefit_enrolments, %i[benefit_id user_id], unique: true, where: "ended_on IS NULL",
              name: "index_hr_lite_benefit_enrolments_one_open", if_not_exists: true
  end
end
