module HrLite
  # Feeds both the admin overview board and the daily leadership digest —
  # one source, so they always agree. Sections return Relations (callers
  # paginate or cap as they see fit).
  class OverviewQuery
    def initialize(date: Date.current)
      @date = date
    end

    def pending_requests
      LeaveRequest.pending.includes(:leave_type, :user).order(:created_at)
    end

    def on_leave_today
      LeaveRequest.active_on(@date).includes(:leave_type, :user).order(:start_date)
    end

    def flagged_today
      AttendanceRecord.for_date(@date).flagged.includes(:user)
    end

    def missing_checkout_yesterday
      AttendanceRecord.for_date(@date - 1).missing_checkout.includes(:user)
    end

    def kpis
      {
        pending: pending_requests.count,
        on_leave: on_leave_today.count,
        flagged: flagged_today.count,
        missing_checkout: missing_checkout_yesterday.count
      }
    end

    def empty?
      kpis.values.all?(&:zero?)
    end
  end
end
