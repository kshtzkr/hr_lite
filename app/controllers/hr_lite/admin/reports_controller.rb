module HrLite
  module Admin
    # The numbers somebody asks for at the end of a month, and the CSV they
    # ask for straight afterwards.
    #
    # Every report is scoped by the SAME permission that guards the screens
    # its data comes from — a report is not a side door into rows somebody
    # cannot otherwise reach.
    class ReportsController < BaseController
      # Finance can approve expenses but runs none of the operations screens,
      # so the operations gate would have shut them out of their own expense
      # report. The hub is reachable by anybody who can see AT LEAST ONE
      # report; each report then checks its own permission.
      skip_before_action :require_operations_access!
      before_action :require_any_report!

      REPORTS = {
        "headcount" => "Headcount by department",
        "joiners_and_leavers" => "Joiners and leavers",
        "leave_balances" => "Leave balances",
        "attendance" => "Attendance summary",
        "expenses" => "Expense claims"
      }.freeze

      def index
        # Only the reports this person could actually open — a list of links
        # that turn you away is worse than a shorter list.
        @reports = REPORTS.select { |name, _| permitted?(name) }
        @month = parse_month_param(params[:month])
      end

      def show
        @month = parse_month_param(params[:month])
        @name = params[:id]
        return hr_access_denied unless REPORTS.key?(@name)
        return hr_access_denied unless permitted?(@name)

        @rows = rows_for(@name)
        respond_to do |format|
          format.html
          format.csv do
            AuditLog.record!(action: "report.exported", subject: hr_current_user,
                             actor: hr_current_user,
                             changes: { "report" => @name, "rows" => @rows.size,
                                        "month" => @month.strftime("%Y-%m") })
            send_data to_csv(@rows), filename: "#{@name}-#{@month.strftime('%Y-%m')}.csv",
                                     type: "text/csv"
          end
        end
      end

      private

      def require_any_report!
        hr_access_denied if REPORTS.keys.none? { |name| permitted?(name) }
      end

      # A report reaches exactly as far as the screen it summarises.
      def permitted?(name)
        case name
        when "expenses" then hr_can?("expense.approve", scope: :all)
        when "leave_balances" then hr_can?("leave.view", scope: :team)
        when "attendance" then hr_can?("attendance.view", scope: :team)
        else hr_can?("profile.view", scope: :team)
        end
      end

      def visible_users
        ids = hr_access.visible_user_ids("profile.view")
        employees = HrLite.employees
        ids.nil? ? employees : employees.select { |user| ids.include?(user.id) }
      end

      def rows_for(name)
        case name
        when "headcount" then headcount_rows
        when "joiners_and_leavers" then joiners_and_leavers_rows
        when "leave_balances" then leave_balance_rows
        when "attendance" then attendance_rows
        when "expenses" then expense_rows
        end
      end

      def headcount_rows
        profiles = EmployeeProfile.where(user_id: visible_users.map(&:id))
                                  .active_for(@month)
        profiles.group_by { |p| p.department.presence || "Unassigned" }
                .sort_by(&:first)
                .map { |department, rows| { "Department" => department, "People" => rows.size } }
      end

      def joiners_and_leavers_rows
        window = @month..@month.end_of_month
        EmployeeProfile.where(user_id: visible_users.map(&:id))
                       .where("date_of_joining BETWEEN ? AND ? OR date_of_exit BETWEEN ? AND ?",
                              window.first, window.last, window.first, window.last)
                       .includes(:user)
                       .map do |profile|
          { "Employee" => HrLite.display_name(profile.user),
            "Department" => profile.department,
            "Joined" => profile.date_of_joining&.to_s,
            "Left" => profile.date_of_exit&.to_s }
        end
      end

      def leave_balance_rows
        year = LeaveYear.key_for(@month)
        types = LeaveType.active.where(paid: true).where.not(annual_quota: nil)
        visible_users.flat_map do |user|
          types.map do |type|
            balance = LeaveBalance.for(user, type, year)
            { "Employee" => HrLite.display_name(user), "Type" => type.code,
              "Entitled" => balance.entitled.to_f, "Used" => balance.used.to_f,
              "Available" => balance.available.to_f }
          end
        end
      end

      def attendance_rows
        visible_users.map do |user|
          summary = AttendanceSummary.for(user: user, month: @month)
          { "Employee" => HrLite.display_name(user),
            "Payable days" => summary[:payable_days].to_f,
            "LOP" => summary[:lop_days].to_f,
            "Days in month" => summary[:days_in_month] }
        end
      end

      def expense_rows
        Expense.where(spent_on: @month..@month.end_of_month)
               .includes(:user, :category).recent_first.map do |expense|
          { "Employee" => HrLite.display_name(expense.user),
            "Category" => expense.category.name,
            "Spent on" => expense.spent_on.to_s,
            "Amount" => expense.amount.to_s("F"),
            "Status" => expense.status }
        end
      end

      def to_csv(rows)
        require "csv"
        return "" if rows.empty?

        CSV.generate do |csv|
          csv << rows.first.keys
          rows.each { |row| csv << row.values }
        end
      end
    end
  end
end
