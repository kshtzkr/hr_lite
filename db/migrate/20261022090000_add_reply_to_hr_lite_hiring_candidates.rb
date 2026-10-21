class AddReplyToHrLiteHiringCandidates < ActiveRecord::Migration[8.1]
  # The candidate's own reply through @interest_link: one token per candidate,
  # their yes/no answers, and the day and 2-hour slot they picked.
  def up
    add_column :hr_lite_hiring_candidates, :interest_token, :string
    add_column :hr_lite_hiring_candidates, :responded_at, :datetime
    add_column :hr_lite_hiring_candidates, :answers, :json, null: false, default: {}
    add_column :hr_lite_hiring_candidates, :preferred_date, :date
    add_column :hr_lite_hiring_candidates, :preferred_slot, :string
    select_values("SELECT id FROM hr_lite_hiring_candidates").each do |id|
      execute "UPDATE hr_lite_hiring_candidates SET interest_token = #{connection.quote(SecureRandom.base58(24))} WHERE id = #{id.to_i}"
    end
    add_index :hr_lite_hiring_candidates, :interest_token, unique: true
    add_index :hr_lite_hiring_candidates, %i[preferred_date preferred_slot]
  end

  def down
    remove_index :hr_lite_hiring_candidates, %i[preferred_date preferred_slot]
    remove_index :hr_lite_hiring_candidates, :interest_token
    remove_column :hr_lite_hiring_candidates, :preferred_slot
    remove_column :hr_lite_hiring_candidates, :preferred_date
    remove_column :hr_lite_hiring_candidates, :answers
    remove_column :hr_lite_hiring_candidates, :responded_at
    remove_column :hr_lite_hiring_candidates, :interest_token
  end
end
