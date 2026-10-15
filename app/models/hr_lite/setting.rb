module HrLite
  # Engine-owned singleton settings row.
  class Setting < ApplicationRecord
    include Audited

    WEEKEND_POLICIES = %w[sun_only sat_sun second_fourth_sat_sun].freeze

    validates :weekend_policy, inclusion: { in: WEEKEND_POLICIES }
    validates :lunch_break_minutes, numericality: { only_integer: true, in: 5..120 }
    validates :short_break_minutes, numericality: { only_integer: true, in: 1..60 }
    # The working day is check-in to check-out, break included (8h30 = 8h + 30m).
    validates :day_minutes, numericality: { only_integer: true, in: 240..720 }
    validates :half_day_below_minutes, numericality: { only_integer: true, greater_than: 0, less_than: :day_minutes }
    validates :recheck_in_from, :recheck_in_until, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "must be HH:MM" }
    validate { errors.add(:recheck_in_until, "must be after the start") if recheck_in_from.to_s >= recheck_in_until.to_s }
    validates :employee_code_prefix, presence: true,
                                     format: { with: /\A[A-Za-z]{1,10}-?\z/, message: "letters only (max 10), optionally ending in -" }

    def self.instance
      first_or_create!
    end

    private

    # The defaults row bootstraps itself on first read — a system action,
    # not a governing change; auditing it would email leadership noise.
    # Real edits (updates) stay fully audited.
    def hr_lite_audit!(action)
      return if action == "create" && HrLite::Current.actor.nil?

      super
    end
  end
end
