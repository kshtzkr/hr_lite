module HrLite
  # Feeds both the admin overview board and the daily leadership digest —
  # one source, so they always agree. Sections return Relations (callers
  # paginate or cap as they see fit).
  class OverviewQuery
    # user_ids nil = everyone; a team-scoped viewer sees only the people they reach.
    def initialize(date: Date.current, user_ids: nil)
      @date = date
      @user_ids = user_ids
    end

    def pending_requests
      reach(LeaveRequest.pending.includes(:leave_type, :user).order(:created_at))
    end

    def on_leave_today
      reach(LeaveRequest.active_on(@date).includes(:leave_type, :user).order(:start_date))
    end

    # Comp-off and regularization are approvals too. Counting leave alone made
    # the board announce "All present and accounted for" while both queues
    # still had work in them.
    def pending_comp_offs
      reach(CompOffRequest.pending.includes(:user).recent_first)
    end

    def pending_regularizations
      reach(RegularizationRequest.pending.includes(:user).recent_first)
    end

    def flagged_today
      reach(AttendanceRecord.for_date(@date).flagged.includes(:user))
    end

    # AttendanceCloseJob fills check_out_at, so the days it closed count too.
    def missing_checkout_yesterday
      yesterday = reach(AttendanceRecord.for_date(@date - 1))
      yesterday.missing_checkout.or(yesterday.where(regularization_note: AttendanceRecord::AUTO_CHECKOUT_NOTE))
               .includes(:user)
    end

    def kpis
      {
        pending: pending_requests.count + pending_comp_offs.count + pending_regularizations.count,
        on_leave: on_leave_today.count,
        flagged: flagged_today.count,
        missing_checkout: missing_checkout_yesterday.count
      }
    end

    def empty?
      kpis.values.all?(&:zero?)
    end

    private

    def reach(relation) = @user_ids ? relation.where(user_id: @user_ids) : relation
  end
end
