module HrLite
  # One box for the whole HRMS: the screens this person may open (the menu's
  # own gates) and the people they may see. Nothing outside their reach is
  # ever listed; a page they still try to open answers as it always does.
  class SearchController < ApplicationController
    MIN_CHARS = 2
    # Words people type that are in neither a tab's label nor its paths (which also match).
    WORDS = {
      "My attendance" => "check in check out punch penalty penalties regularization fix late",
      "My leave" => "apply leave holiday comp-off balance", "Calendar" => "holidays",
      "WFH" => "work from home", "Home locations" => "wfh location", "Slips" => "payslip salary slip",
      "Expenses" => "claim reimbursement", "Employees" => "people staff", "Profile" => "my details",
      "Settings" => "working day half day penalties leave type check in again"
    }.freeze

    rate_limit to: 60, within: 1.minute, by: -> { hr_current_user.id }, name: "hr_search"

    def show
      @q = params[:q].to_s.strip
      words = @q.downcase.split
      limit = params[:frame] ? 5 : 10
      @features = @people = []
      if @q.length >= MIN_CHARS
        @features = helpers.hrl_sections.flat_map { |s| s[:tabs].map { |t| [ "#{s[:label]} · #{t[:label]}", public_send(t[:path]), "#{s[:label]} #{t[:label]} #{WORDS[t[:label]]} #{Array(t[:match]).join(' ').tr('/_', '  ')}".downcase ] } }
                           .select { |_, _, text| words.all? { |w| text.include?(w) } }.first(limit)
        @people = people_matching(words).first(limit) if hr_operations?
      end
      params[:frame] ? render(partial: "results") : render(:show)
    end

    private

    # Only people whose attendance this viewer may open; the result opens their This week.
    def people_matching(words)
      codes = EmployeeProfile.pluck(:user_id, :employee_code).to_h
      HrLite.employees.select do |user|
        text = [ HrLite.display_name(user), user.email, codes[user.id] ].join(" ").downcase
        words.all? { |w| text.include?(w) } && hr_reaches?("attendance.view", user)
      end
    end
  end
end
