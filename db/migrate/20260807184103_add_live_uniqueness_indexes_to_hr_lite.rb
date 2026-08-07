class AddLiveUniquenessIndexesToHrLite < ActiveRecord::Migration[8.0]
  # The models already validate each of these, but a validation is a
  # read-then-write: two concurrent requests both see nothing and both insert.
  # Comp-off requests already had this partial index; these three did not.
  #
  # Every table here holds a handful of rows per employee, so the index builds
  # are instant and a plain (non-concurrent) build is fine.
  def change
    # One open resignation per person — Resignation#single_open_resignation.
    add_index :hr_lite_resignations, :user_id,
              unique: true,
              where: "status = 'pending'",
              name: "index_hr_lite_resignations_one_pending_per_user"

    # One ticket per person per day — RegularizationRequest#no_duplicate_pending.
    add_index :hr_lite_regularization_requests, %i[user_id date],
              unique: true,
              where: "status = 'pending'",
              name: "index_hr_lite_regularizations_one_pending_per_day"

    # Exactly one leave type carries the comp-off flag — approvals credit into
    # THE comp-off type, and two would make the target position-order roulette.
    add_index :hr_lite_leave_types, :comp_off,
              unique: true,
              where: "comp_off",
              name: "index_hr_lite_leave_types_single_comp_off"
  end
end
