module HrLite
  class AttendanceRecord < ApplicationRecord
    STATUSES = %w[present half_day].freeze
    AUTO_CHECKOUT_NOTE = "Auto check-out: no check-out punched".freeze
    SHORT_DAY_NOTE = "Short day: under the required hours".freeze
    LATE_HALF_DAY_NOTE = "Half day: checked in after 11:30".freeze
    # Half days the system set (not HR); an approved ticket lifts them.
    AUTO_NOTES = [ AUTO_CHECKOUT_NOTE, SHORT_DAY_NOTE, LATE_HALF_DAY_NOTE ].freeze
    # Where the day was worked, set at check-in under config.office_geofence.
    WORK_MODES = { "office" => "Office", "wfh" => "WFH", "travelling" => "Travelling",
                   "outside_meeting" => "Client meeting" }.freeze
    # Check-in and check-out further apart than this are called out on the board.
    PUNCH_GAP_ALERT_M = 500
    # Where each punch happened, set by AttendancePuncher.
    PLACES = { "office" => "Office", "home" => "Home", "travel" => "Travel" }.freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :regularized_by, class_name: HrLite.config.user_class, optional: true
    belongs_to :wfh_request, optional: true
    belongs_to :work_location, optional: true
    belongs_to :check_out_work_location, class_name: "HrLite::WorkLocation", optional: true

    def remote? = work_mode.present? && work_mode != "office"
    def work_mode_label = WORK_MODES[work_mode]
    def place_label(side) = PLACES[public_send("#{side}_place")]

    # The day's start and end as a Google Maps route, one tap from the trail.
    def route_url
      return unless check_in_lat && check_in_lng && check_out_lat && check_out_lng

      "https://www.google.com/maps/dir/?api=1&origin=#{check_in_lat},#{check_in_lng}&destination=#{check_out_lat},#{check_out_lng}"
    end

    validates :date, presence: true, uniqueness: { scope: :user_id }
    validates :status, inclusion: { in: STATUSES }
    validates :half_day_part, inclusion: { in: %w[first second] }, allow_blank: true
    validate :check_out_after_check_in
    validate :times_on_the_day, if: -> { will_save_change_to_date? || will_save_change_to_check_in_at? || will_save_change_to_check_out_at? }

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

    # The working day HR sets in Settings, less the person's allowance. Nil when
    # the host turns hours rules off (config.work_hours), and on Saturdays.
    def required_minutes
      EmployeeProfile.day_minutes_for(user_id, on: date) unless HrLite.config.work_hours.nil? || date.saturday?
    end

    # Hours worked, not the clock: an early start counts. The day's penalty
    # minutes count too, the same rule as required_check_out_at, so the card
    # never says "day done" above "short by 20m".
    def short?
      worked_under?(required_minutes && required_minutes + penalty_minutes)
    end

    def below_half_day?
      worked_under?(required_minutes && Setting.instance.half_day_below_minutes)
    end

    # config.attendance_slots: first check-in + the working day + the day's active penalties.
    def required_check_out_at
      return unless HrLite.config.attendance_slots && check_in_at

      check_in_at + (EmployeeProfile.day_minutes_for(user_id, on: date) + penalty_minutes).minutes
    end

    def penalty_minutes = AttendancePenalty.active.where(user_id: user_id, date: date).sum(:minutes)

    def worked_under?(minutes) = !!(minutes && worked_duration && worked_duration < minutes.minutes)

    # Check in again after checking out: once a day, inside the hours HR sets in
    # Settings, and only while the day is short (a full day has nothing to add).
    def recheck_in_open?(at = Time.current)
      return false if required_minutes && !short?

      s = Setting.instance
      now = at.in_time_zone(HrLite.config.time_zone).strftime("%H:%M")
      check_out_at.present? && rechecked_in_at.nil? && now >= s.recheck_in_from && now < s.recheck_in_until
    end

    # Every check-in and check-out of the day, oldest first, kept even after an HR reset.
    def punches = AttendancePunch.where(user_id: user_id, date: date).order(:at, :id).to_a

    # Drops the check-out so the person is in again (check in again, HR reset).
    def clear_check_out(**attrs)
      assign_attributes(check_out_at: nil, check_out_lat: nil, check_out_lng: nil, check_out_accuracy_m: nil,
                        check_out_place: nil, check_out_home_m: nil, check_out_work_location_id: nil, **attrs)
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

    # No future days; check-out may run into the next morning (night shift).
    # Only the fields being changed, in the company's zone, so re-saving an old row never fails.
    def times_on_the_day
      return unless date

      day = ->(time) { time.in_time_zone(HrLite.config.time_zone).to_date }
      errors.add(:date, "can't be in the future") if will_save_change_to_date? && date > day.(Time.current)
      errors.add(:check_in_at, "must be on #{date.strftime('%d %b')}") if will_save_change_to_check_in_at? && check_in_at && day.(check_in_at) != date
      if will_save_change_to_check_out_at? && check_out_at && !(date..date + 1).cover?(day.(check_out_at))
        errors.add(:check_out_at, "must be on #{date.strftime('%d %b')} or the next morning")
      end
    end
  end
end
