class AddInterviewersToHrLiteHiringInterviews < ActiveRecord::Migration[8.1]
  # The other people invited to an interview round, by email (staff picked
  # from the system or typed in). They are guests on the same calendar event.
  def change
    add_column :hr_lite_hiring_interviews, :interviewers, :json, null: false, default: []
  end
end
