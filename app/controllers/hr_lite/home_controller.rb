module HrLite
  class HomeController < ApplicationController
    def index
      @latest_kudos = Kudo.recent.includes(:giver, kudo_mentions: :user).limit(3)
      @out_week = LeaveRequest.approved.overlapping_range(Date.current.beginning_of_week, Date.current.end_of_week)
                              .includes(:user).where(user_id: HrLite.active_employees.map(&:id))
                              .sort_by { |leave| hr_display_name(leave.user).downcase }
      @attention = attention_days
      @waiting = Approval.pending_for(hr_current_user).count
      @queue = queue_count
      @mine_pending = [ LeaveRequest.includes(:leave_type), RegularizationRequest, CompOffRequest ]
                      .flat_map { |scope| scope.pending.where(user_id: hr_current_user.id).order(created_at: :desc).limit(5) }
                      .max_by(5, &:created_at)
    end

    private

    # Requests with no routed flow are decided straight off the HR queues, scoped as those queues decide them.
    def queue_count
      leave = ApprovalFlow.for(LeaveRequest.name) ? 0 : decidable(LeaveRequest, "leave.approve")
      leave + decidable(CompOffRequest, "leave.approve") + decidable(RegularizationRequest, "attendance.manage")
    end

    def decidable(model, key) = hr_scope(model.pending, key).where.not(user_id: hr_current_user.id).count

    # Last week's days that still need a fix (absent, no check-out, flagged, short), minus those with a pending ticket.
    def attention_days
      range = (Date.current - 7)..(Date.current - 1)
      days = DayStatus.new(user: hr_current_user, range: range)
      pending = RegularizationRequest.pending.where(user_id: hr_current_user.id, date: range).pluck(:date)
      profile = EmployeeProfile.find_by(user_id: hr_current_user.id)
      (range.to_a - pending).filter_map do |date|
        day = days.for(date)
        # The day card offers no Fix on these; days outside employment are not absences.
        next if %i[holiday weekend leave].include?(day.kind) || (profile && !profile.active_on?(date))

        # Yesterday's open shift may still be running; the punch card offers its check-out.
        reason = if day.kind == :absent then "Absent"
        elsif day.record&.check_in_at && !day.record.check_out_at && date < Date.current - 1 then "No check-out"
        elsif day.record&.flagged? then "Flagged"
        elsif day.record&.short? && !day.record.regularized? then "Short day"
        end
        [ date, reason ] if reason
      end
    end
  end
end
