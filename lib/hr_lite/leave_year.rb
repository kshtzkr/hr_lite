module HrLite
  # The leave year is the 12-month window balances live in. It starts on
  # config.leave_year_start_month (1 = calendar year, 7 = July–June, the
  # Indian travel-industry pattern). A year is identified by the calendar
  # year its FIRST month falls in: with July starts, key 2026 spans
  # 1 Jul 2026 – 30 Jun 2027.
  module LeaveYear
    module_function

    def start_month
      HrLite.config.leave_year_start_month
    end

    # The key (integer label) of the leave year containing `date`.
    def key_for(date)
      date.month >= start_month ? date.year : date.year - 1
    end

    def current_key
      key_for(Date.current)
    end

    def range(key)
      start = Date.new(key, start_month, 1)
      start..(start >> 12) - 1
    end

    # "2026" for calendar years, "2026–27" otherwise.
    def label(key)
      start_month == 1 ? key.to_s : format("%d–%02d", key, (key + 1) % 100)
    end
  end
end
