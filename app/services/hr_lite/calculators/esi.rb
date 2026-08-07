module HrLite
  module Calculators
    # ESI: eligibility is decided on the FULL structure monthly gross (a
    # low-attendance month must not pull someone into ESI), and specifically
    # on the gross in force at the START of the ESIC contribution period —
    # April–September or October–March. A rise past the ceiling mid-period
    # does not end coverage; the caller resolves that period-start gross and
    # passes it here. Contributions apply to the EARNED gross and round up to
    # the next rupee (ESIC rule).
    module Esi
      Result = Struct.new(:applicable, :employee, :employer, keyword_init: true) do
        def applicable? = applicable
      end

      def self.call(monthly_gross:, gross_earned:, applicable:, rates:)
        eligible = applicable && Money.d(monthly_gross) <= rates[:gross_ceiling]
        return Result.new(applicable: false, employee: BigDecimal(0), employer: BigDecimal(0)) unless eligible

        earned = Money.d(gross_earned)
        Result.new(
          applicable: true,
          employee: Money.ceil_rupee(earned * rates[:employee_rate]),
          employer: Money.ceil_rupee(earned * rates[:employer_rate])
        )
      end
    end
  end
end
