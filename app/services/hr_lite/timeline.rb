module HrLite
  # One employee's year as `viewer` may see it, split into what everyone may
  # read (#public_events) and what only the employee and whoever the matching
  # permission reaches may read (#private_events). Leave type follows
  # leave.view, like the "Out in the next 2 weeks" card.
  class Timeline
    Event = Struct.new(:date, :category, :title, :detail, keyword_init: true)

    PAY_CODES = %w[bonus incentive arrears].freeze

    def initialize(user:, viewer:, year:)
      @user = user
      @viewer = viewer
      @range = Date.new(year)..Date.new(year).end_of_year
    end

    def public_events = newest_first(lifecycle + promotions + kudos_received + kudos_given + awards + leaves)

    def private_events
      newest_first(pay_items + loans + expenses + appraisals + plans + attendance_fixes + comp_offs +
                   assets + documents + resignations + probation + hr_requests + open_leave)
    end

    private

    def newest_first(events) = events.select { |e| @range.cover?(e.date) }.sort_by { |e| -e.date.jd }

    def visible?(key)
      @viewer.id == @user.id || HrLite.reaches?(@viewer, key, @user)
    end

    def mine = { user_id: @user.id }
    def days = @range.begin.beginning_of_day..@range.end.end_of_day
    def event(date, category, title, detail = nil) = Event.new(date: date, category: category, title: title, detail: detail.presence)
    def profile = @profile ||= EmployeeProfile.find_by(user_id: @user.id)

    # --- public ---------------------------------------------------------------

    def lifecycle
      return [] unless profile

      [ [ profile.date_of_joining, "Joined the company" ], [ profile.date_of_exit, "Left the company" ] ]
        .select { |date, _| date && date <= Date.current }
        .map { |date, title| event(date, "Milestone", title) }
    end

    def promotions
      DesignationChange.where(**mine, effective_date: @range.begin..[ @range.end, Date.current ].min).map do |change|
        event(change.effective_date, "Promotion", "New role: #{change.to_designation}",
              change.from_designation.presence && "from #{change.from_designation}")
      end
    end

    def kudos_received
      Kudo.joins(:kudo_mentions).where(hr_lite_kudo_mentions: mine, created_at: days).includes(:giver).map do |kudo|
        event(kudo.created_at.to_date, "Kudos", "Kudos from #{HrLite.display_name(kudo.giver)}", kudo_text(kudo))
      end
    end

    def kudos_given
      Kudo.where(giver_id: @user.id, created_at: days).includes(:mentioned_users).map do |kudo|
        names = kudo.mentioned_users.map { |u| HrLite.display_name(u) }.to_sentence
        event(kudo.created_at.to_date, "Kudos", "Gave kudos#{" to #{names}" if names.present?}", kudo_text(kudo))
      end
    end

    def kudo_text(kudo) = [ kudo.badge_label, MentionParser.strip_markers(kudo.message) ].compact.join(" · ")

    def awards
      Award.where(**mine, period_start: @range).map do |award|
        event(award.period_start, "Award", "#{award.title} — #{award.period_label}", award.citation)
      end
    end

    def leaves
      typed = visible?("leave.view")
      LeaveRequest.approved.where(mine).overlapping_range(@range.begin, @range.end).includes(:leave_type).map do |leave|
        event(leave.start_date, "Leave", typed ? leave.leave_type.name : "On leave", leave.date_range_label)
      end
    end

    # --- private --------------------------------------------------------------

    def pay_items
      return [] unless visible?("payroll.view")

      PayrollLineItem.joins(:component).includes(:component).where(**mine, period_month: @range)
                     .where(hr_lite_salary_components: { code: PAY_CODES }).map do |item|
        event(item.period_month, "Pay", item.component.label, [ Money.format(item.amount), item.note.presence ].compact.join(" · "))
      end
    end

    def loans
      return [] unless visible?("payroll.view")

      Loan.where(**mine, starts_on: @range).map { |loan| event(loan.starts_on, "Pay", "Loan of #{Money.format(loan.principal)}", loan.reason) }
    end

    def expenses
      return [] unless visible?("expense.approve")

      Expense.where(**mine, status: %w[approved reimbursed], spent_on: @range).includes(:category).map do |expense|
        event(expense.spent_on, "Expense", "Expense #{expense.status}: #{expense.category.name}",
              "#{Money.format(expense.amount)} · #{expense.description}")
      end
    end

    def appraisals
      return [] unless visible?("appraisal.view")

      Appraisal.shared.where(**mine, shared_at: days).map do |appraisal|
        outcome = appraisal.outcome == "none" ? nil : appraisal.outcome.humanize
        event(appraisal.shared_at.to_date, "Performance", "Appraisal #{appraisal.period_label}",
              [ appraisal.rating && "Rating #{appraisal.rating}/5", outcome ].compact.join(" · "))
      end
    end

    def plans
      return [] unless visible?("appraisal.view")

      PerformancePlan.where(mine).where(start_date: ..@range.end).flat_map do |plan|
        [ event(plan.start_date, "Performance", "Performance improvement plan started", "Until #{plan.end_date.strftime('%d %b %Y')}"),
          plan.closed_at && event(plan.closed_at.to_date, "Performance", "Performance improvement plan #{plan.status}", plan.outcome_note) ].compact
      end
    end

    # Leave that never happened: still waiting, or turned down.
    def open_leave
      return [] unless visible?("leave.view")

      LeaveRequest.where(**mine, status: %w[pending rejected]).overlapping_range(@range.begin, @range.end).includes(:leave_type).map do |leave|
        event(leave.start_date, "Leave", "#{leave.leave_type.name} — #{leave.status}", leave.date_range_label)
      end
    end

    def attendance_fixes
      return [] unless visible?("attendance.view")

      RegularizationRequest.where(**mine, status: "approved", date: @range).map do |fix|
        event(fix.date, "Attendance", "Attendance fixed (#{fix.times_label})", fix.reason)
      end
    end

    def comp_offs
      return [] unless visible?("leave.view")

      CompOffRequest.where(**mine, status: "approved", date_worked: @range).map do |comp_off|
        event(comp_off.date_worked, "Leave", "Comp-off earned (#{comp_off.credit_days} day)", comp_off.reason)
      end
    end

    def assets
      return [] unless visible?("asset.view")

      AssetAssignment.where(mine).includes(:asset).flat_map do |held|
        [ event(held.assigned_on, "Asset", "Given #{held.asset.name}", held.asset.serial_number),
          held.returned_on && event(held.returned_on, "Asset", "Returned #{held.asset.name}", held.condition_note) ].compact
      end
    end

    def documents
      Document.where(**mine, verification: "verified", verified_at: days).select { |doc| doc.readable_by?(@viewer) }.map do |doc|
        event(doc.verified_at.to_date, "Document", "Document verified: #{doc.title}")
      end
    end

    def resignations
      return [] unless visible?("resignation.view")

      Resignation.where(mine).flat_map do |resignation|
        accepted = resignation.status == "accepted" && resignation.decided_at
        [ event(resignation.created_at.to_date, "Exit", "Resigned", "Proposed last day #{resignation.proposed_last_day.strftime('%d %b %Y')}"),
          accepted && event(resignation.decided_at.to_date, "Exit", "Resignation accepted",
                            "Last day #{resignation.proposed_last_day.strftime('%d %b %Y')}") ].select(&:itself)
      end
    end

    def probation
      return [] unless profile&.probation_until && visible?("profile.view")

      [ event(profile.probation_until, "Milestone", profile.probation_until < Date.current ? "Probation ended" : "Probation ends") ]
    end

    def hr_requests
      return [] unless visible?("hr_request.manage")

      HrRequest.where(**mine, status: %w[resolved closed], resolved_at: days).map do |request|
        event(request.resolved_at.to_date, "Help desk", "Request resolved: #{request.subject}", request.resolution)
      end
    end
  end
end
