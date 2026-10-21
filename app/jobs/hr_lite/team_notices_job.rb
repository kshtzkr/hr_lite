module HrLite
  # 10am email to every current employee: who is on leave today, whose
  # birthday it is. Each goes only when its list has someone on it.
  class TeamNoticesJob < ApplicationJob
    queue_as :default

    def perform(date: Date.current)
      staff = HrLite.active_employees(on: date)
      out = LeaveRequest.where(status: %w[pending approved], user_id: staff.map(&:id))
                        .overlapping_range(date, date).includes(:user)
      announce("leave.out_today", "On leave today", staff, date,
               out.map { |l| "#{HrLite.display_name(l.user)} — #{l.date_range_label}#{' (pending approval)' if l.pending?}" })
      announce("birthday.today", "Birthdays today", staff, date,
               EmployeeProfile.birthdays_in(date..date).map { |p, _| "Happy birthday, #{HrLite.display_name(p.user)}" })
    end

    private

    def announce(event, title, staff, date, lines)
      return if lines.empty?

      Notifications.publish(event, title: "#{title} — #{date.strftime('%a %-d %b')}", lines: lines.sort,
                                   email_to: staff, path: "/")
    end
  end
end
