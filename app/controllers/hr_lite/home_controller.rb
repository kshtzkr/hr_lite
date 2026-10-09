module HrLite
  class HomeController < ApplicationController
    def index
      @latest_kudos = Kudo.recent.includes(:giver, kudo_mentions: :user).limit(3)
      @out_week = LeaveRequest.approved.overlapping_range(Date.current.beginning_of_week, Date.current.end_of_week)
                              .includes(:user).where(user_id: HrLite.active_employees.map(&:id))
                              .sort_by { |leave| hr_display_name(leave.user).downcase }
      @attention = attention_days
    end

    private

    # Last week's days that still need a fix (absent, no check-out, flagged), minus those with a pending ticket.
    def attention_days
      range = (Date.current - 7)..(Date.current - 1)
      days = DayStatus.new(user: hr_current_user, range: range)
      pending = RegularizationRequest.pending.where(user_id: hr_current_user.id, date: range).pluck(:date)
      (range.to_a - pending).filter_map do |date|
        day = days.for(date)
        reason = if day.kind == :absent then "Absent"
        elsif day.record&.check_in_at && !day.record.check_out_at then "No check-out"
        elsif day.record&.flagged? then "Flagged"
        end
        [ date, reason ] if reason
      end
    end
  end
end
