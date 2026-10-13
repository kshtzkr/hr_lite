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

    def label = REASONS.fetch(reason)
  end
end
