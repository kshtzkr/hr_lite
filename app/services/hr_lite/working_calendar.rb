module HrLite
  # The single source of day classification. Preloads holidays and the
  # weekend policy once per instance; every other service (leave counting,
  # day status, attendance summary) delegates here.
  class WorkingCalendar
    def initialize(range)
      @range = range
      @holiday_dates = Holiday.dates_for(range)
      @policy = Setting.instance.weekend_policy
    end

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
