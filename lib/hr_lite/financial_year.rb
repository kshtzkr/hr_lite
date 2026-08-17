module HrLite
  # The Indian financial year runs 1 April – 31 March. Three places worked
  # this out for themselves (the slip's year-to-date sums, the TDS projector
  # and the rate card); it lives here once so they cannot drift apart.
  module FinancialYear
    START_MONTH = 4

    # First day of the FY containing `date`. March 2027 belongs to the year
    # that opened on 1 April 2026.
    def self.start_for(date)
      year = date.month >= START_MONTH ? date.year : date.year - 1
      Date.new(year, START_MONTH, 1)
    end

    # "2026-27" — for warnings and screens, never for arithmetic.
    def self.label(date)
      start = start_for(date)
      "#{start.year}-#{format('%02d', (start.year + 1) % 100)}"
    end

    # True when `date` falls in an earlier FY than `other`.
    def self.before?(date, other)
      start_for(date) < start_for(other)
    end
  end
end
