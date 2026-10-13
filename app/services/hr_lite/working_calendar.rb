module HrLite
  # The single source of day classification. Preloads holidays and the
  # weekend policy once per instance; every other service (leave counting,
  # day status, attendance summary) delegates here.
  class WorkingCalendar
    # office_id: that office's holidays count too (nil = all-office ones only).
    def initialize(range, office_id: nil)
      @range = range
      @holiday_dates = Holiday.dates_for(range, office_id)
      @policy = Setting.instance.weekend_policy
    end

    def self.office_for(user_id) = EmployeeProfile.where(user_id: user_id).pick(:office_location_id)

    # One person's calendar: their office's holidays plus the all-office ones.
    def self.for_user(user_id, range) = new(range, office_id: office_for(user_id))

    # Many people at once: one calendar per office, built on first use.
    def self.by_office(range) = Hash.new { |h, office_id| h[office_id] = new(range, office_id: office_id) }

    def holiday?(date)
      @holiday_dates.include?(date)
    end

    def weekend?(date)
      case @policy
      when "sun_only"
        date.sunday?
      when "second_fourth_sat_sun"
        date.sunday? || (date.saturday? && [ 2, 4 ].include?(week_of_month(date)))
      else # sat_sun
        date.saturday? || date.sunday?
      end
    end

    def working_day?(date)
      !holiday?(date) && !weekend?(date)
    end

    def working_days_in(range)
      range.count { |date| working_day?(date) }
    end

    private

    def week_of_month(date)
      ((date.day - 1) / 7) + 1
    end
  end
end
