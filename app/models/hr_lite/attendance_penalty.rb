module HrLite
  # Minutes added to one day's required checkout. Never deleted: HR removes
  # one with a reason and the row stays as the record.
  class AttendancePenalty < ApplicationRecord
    include Audited

    REASONS = {
      "late" => "Late check-in",
      "late_carry" => "Checked in after 11:00",
      "short_day" => "Left before the required checkout"
    }.freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :attendance_record
    belongs_to :removed_by, class_name: HrLite.config.user_class, optional: true

    validates :reason, inclusion: { in: REASONS.keys }
    validates :minutes, numericality: { greater_than: 0 }
    validates :removal_reason, presence: true, if: :removed_at

    scope :active, -> { where(removed_at: nil) }

    def self.next_working_days(user_id, date, count)
      calendar = WorkingCalendar.for_user(user_id, (date + 1)..(date + 31))
      ((date + 1)..(date + 31)).select { |d| calendar.working_day?(d) }.first(count)
    end

    # Penalty minutes still held per person: every active penalty ever, less the
    # hours HR removed. They build up until HR removes them; never below 0.
    def self.held_minutes(user_ids)
      removed = PenaltyRemoval.where(user_id: user_ids).group(:user_id).sum(:minutes)
      active.where(user_id: user_ids).group(:user_id).sum(:minutes).to_h { |id, m| [ id, [ m - removed[id].to_i, 0 ].max ] }
    end

    # Every 5h held is half a day of leave: 7h = 0.5, 10h = 1, 100h = 10.
    def self.days_for(minutes) = (minutes / 300) * 0.5

    def label = REASONS.fetch(reason)

    # Why this row exists, naming the day and punch that caused it.
    def cause
      r = attendance_record
      t = ->(at) { at.nil? ? "—" : at.in_time_zone(HrLite.config.time_zone).then { |l| l.strftime(l.to_date == r.date ? "%H:%M" : "%H:%M on %a %-d %b") } }
      on = r.date.strftime("%a %-d %b")
      why = case reason
      when "late" then "You checked in at #{t[r.check_in_at]} on #{on}, after your slot."
      when "late_carry" then "You checked in at #{t[r.check_in_at]} on #{on}, after 11:00, so +1h goes on your next 2 working days."
      else "You checked out at #{t[r.check_out_at]} on #{on}, before that day's required checkout of #{t[r.required_check_out_at]}."
      end
      "#{why} So #{date.strftime('%a %-d %b')} needs #{minutes} min more before checkout."
    end
  end
end
