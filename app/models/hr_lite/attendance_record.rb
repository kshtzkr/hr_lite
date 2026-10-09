module HrLite
  class AttendanceRecord < ApplicationRecord
    STATUSES = %w[present half_day].freeze
    AUTO_CHECKOUT_NOTE = "Auto check-out: no check-out punched".freeze
    SHORT_DAY_NOTE = "Short day: under the required hours".freeze
    # Half days the close job set (not HR); an approved ticket lifts them.
    AUTO_NOTES = [ AUTO_CHECKOUT_NOTE, SHORT_DAY_NOTE ].freeze
    # Check-in and check-out further apart than this are called out on the board.
    PUNCH_GAP_ALERT_M = 500

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :regularized_by, class_name: HrLite.config.user_class, optional: true

    validates :date, presence: true, uniqueness: { scope: :user_id }
    validates :status, inclusion: { in: STATUSES }
    validates :half_day_part, inclusion: { in: %w[first second] }, allow_blank: true
    validate :check_out_after_check_in

    scope :for_date, ->(date) { where(date: date) }
    scope :for_month, ->(month) { where(date: month.beginning_of_month..month.end_of_month) }
    scope :flagged, -> { where(flagged: true) }
    scope :missing_checkout, -> { where.not(check_in_at: nil).where(check_out_at: nil) }

    def regularized?
      regularized_at.present?
    end

    def worked_duration
      return nil unless check_in_at && check_out_at

      check_out_at - check_in_at
    end

    # config.work_hours: probation days need more hours. Nil when the rule is
    # off, and on Saturdays (a working Saturday has no hours rule).
    def required_hours
      rule = HrLite.config.work_hours
      return if rule.nil? || date.saturday?

      EmployeeProfile.find_by(user_id: user_id)&.on_probation?(date) ? rule[:probation_day] : rule[:day]
    end

    def short?
      hours = required_hours
      !!(hours && worked_duration && worked_duration < hours.hours)
    end

    # Metres between where the day was checked in and checked out.
    def punch_gap_m
      return unless check_in_lat && check_in_lng && check_out_lat && check_out_lng

      Geo.distance_m(check_in_lat, check_in_lng, check_out_lat, check_out_lng)
    end

    def add_flag!(note)
      self.flagged = true
      self.flag_note = [ flag_note.presence, note ].compact.join("; ")
    end

    private

    def check_out_after_check_in
      return unless check_in_at && check_out_at
      return if check_out_at >= check_in_at

      errors.add(:check_out_at, "must be after check-in")
    end
  end
end
