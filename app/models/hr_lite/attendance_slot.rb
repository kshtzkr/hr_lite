module HrLite
  # The check-in slot an employee commits to for a day, week or month.
  # Saving locks it; only an attendance manager changes or unlocks it.
  class AttendanceSlot < ApplicationRecord
    include Audited

    START_MINUTES = [ 540, 570, 600, 630 ].freeze # 09:00 09:30 10:00 10:30
    DEFAULT_START_MINUTE = 600
    PERIODS = { "day" => "Today", "week" => "This week", "month" => "This month" }.freeze
    DAY_MINUTES = 510 # 8h30m from slot to checkout
    GRACE_MINUTES = 5
    STEP_MINUTES = 30
    CARRY_AFTER_MINUTE = 660 # 11:00 — +1h on the next 2 working days
    HALF_DAY_AFTER_MINUTE = 690 # 11:30 — the day is a half day

    belongs_to :user, class_name: HrLite.config.user_class

    validates :start_minute, inclusion: { in: START_MINUTES }
    validates :period, inclusion: { in: PERIODS.keys }
    validates :starts_on, :ends_on, presence: true

    scope :overlapping, ->(from, to) { where("starts_on <= ? AND ends_on >= ?", to, from) }

    def self.current(user_id, date) = where(user_id: user_id).overlapping(date, date).order(:created_at).last
    def self.start_minute_for(user_id, date) = current(user_id, date)&.start_minute || DEFAULT_START_MINUTE

    def self.ends_on_for(period, from)
      { "week" => from.end_of_week(:monday), "month" => from.end_of_month }.fetch(period, from)
    end

    # 0 within grace, then +30 for every started half hour: 6–35 late = 30, 36–65 = 60.
    def self.penalty_minutes(late)
      late <= GRACE_MINUTES ? 0 : STEP_MINUTES * ((late - GRACE_MINUTES) / STEP_MINUTES.to_f).ceil
    end

    def self.label(minute) = format("%02d:%02d", *minute.divmod(60))
  end
end
