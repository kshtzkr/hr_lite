module HrLite
  # One employee's year, newest first, as `viewer` may see it. Joining, exit,
  # role changes, kudos, awards and leave dates are public; pay items, loans,
  # expenses, appraisals and PIPs show only to the employee and to whoever the
  # matching permission reaches. Leave type follows leave.view, like the
  # "Out in the next 2 weeks" card.
  class Timeline
    Event = Struct.new(:date, :title, :detail, :sensitive, keyword_init: true)

    PAY_CODES = %w[bonus incentive arrears].freeze

    def initialize(user:, viewer:, year:)
      @user = user
      @viewer = viewer
      @range = Date.new(year)..Date.new(year).end_of_year
    end

    def events
      (lifecycle + promotions + kudos + awards + leaves + pay_items + loans + expenses + appraisals + plans)
        .sort_by { |event| -event.date.jd }
    end

    private

    def visible?(key)
      @viewer.id == @user.id || HrLite.reaches?(@viewer, key, @user)
    end

    def mine = { user_id: @user.id }

    def lifecycle
      profile = EmployeeProfile.find_by(user_id: @user.id)
      return [] unless profile

      [ [ profile.date_of_joining, "Joined" ], [ profile.date_of_exit, "Left the company" ] ]
        .select { |date, _| date && @range.cover?(date) && date <= Date.current }
        .map { |date, title| Event.new(date: date, title: title) }
    end

    def promotions
      DesignationChange.where(mine).where(effective_date: @range.begin..[ @range.end, Date.current ].min).map do |change|
        Event.new(date: change.effective_date, title: "New role: #{change.to_designation}",
                  detail: change.from_designation.presence && "from #{change.from_designation}")
      end
    end

    def kudos
      Kudo.joins(:kudo_mentions).where(hr_lite_kudo_mentions: mine, created_at: @range.begin.beginning_of_day..@range.end.end_of_day)
          .includes(:giver).map do |kudo|
        Event.new(date: kudo.created_at.to_date, title: "Kudos from #{HrLite.display_name(kudo.giver)}",
                  detail: [ kudo.badge_label, MentionParser.strip_markers(kudo.message) ].compact.join(" · "))
      end
    end

    def awards
      Award.where(**mine, period_start: @range).map do |award|
        Event.new(date: award.period_start, title: "#{award.title} — #{award.period_label}", detail: award.citation)
      end
    end

    def leaves
      typed = visible?("leave.view")
      LeaveRequest.approved.where(mine).overlapping_range(@range.begin, @range.end).includes(:leave_type).map do |leave|
        Event.new(date: leave.start_date, title: typed ? leave.leave_type.name : "On leave", detail: leave.date_range_label)
      end
    end

    def pay_items
      return [] unless visible?("payroll.view")

      PayrollLineItem.joins(:component).includes(:component).where(**mine, period_month: @range)
                     .where(hr_lite_salary_components: { code: PAY_CODES }).map do |item|
        Event.new(date: item.period_month, title: item.component.label, detail: [ Money.format(item.amount), item.note.presence ].compact.join(" · "), sensitive: true)
      end
    end

    def loans
      return [] unless visible?("payroll.view")

      Loan.where(**mine, starts_on: @range).map do |loan|
        Event.new(date: loan.starts_on, title: "Loan of #{Money.format(loan.principal)}", detail: loan.reason, sensitive: true)
      end
    end

    def expenses
      return [] unless visible?("expense.approve")

      Expense.where(**mine, status: %w[approved reimbursed], spent_on: @range).includes(:category).map do |expense|
        Event.new(date: expense.spent_on, title: "Expense #{expense.status}: #{expense.category.name}",
                  detail: "#{Money.format(expense.amount)} · #{expense.description}", sensitive: true)
      end
    end

    def appraisals
      return [] unless visible?("appraisal.view")

      Appraisal.shared.where(**mine, shared_at: @range.begin.beginning_of_day..@range.end.end_of_day).map do |appraisal|
        outcome = appraisal.outcome == "none" ? nil : appraisal.outcome.humanize
        Event.new(date: appraisal.shared_at.to_date, title: "Appraisal #{appraisal.period_label}",
                  detail: [ appraisal.rating && "Rating #{appraisal.rating}/5", outcome ].compact.join(" · "), sensitive: true)
      end
    end

    def plans
      return [] unless visible?("appraisal.view")

      PerformancePlan.where(mine).where(start_date: ..@range.end).flat_map do |plan|
        started = Event.new(date: plan.start_date, title: "Performance improvement plan started",
                            detail: "Until #{plan.end_date.strftime('%d %b %Y')}", sensitive: true)
        closed = plan.closed_at && Event.new(date: plan.closed_at.to_date, title: "Performance improvement plan #{plan.status}",
                                             detail: plan.outcome_note, sensitive: true)
        [ started, closed ].compact.select { |event| @range.cover?(event.date) }
      end
    end
  end
end
