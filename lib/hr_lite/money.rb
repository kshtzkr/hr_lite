module HrLite
  # Central rounding discipline. Each statutory line rounds by its own rule
  # exactly once; nets are plain subtraction of already-rounded lines.
  module Money
    module_function

    def d(value)
      return BigDecimal(0) if value.nil?

      value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
    end

    # Nearest rupee, half-up (PF, TDS monthly).
    def round_rupee(value)
      d(value).round(0, BigDecimal::ROUND_HALF_UP)
    end

    # Next rupee (ESIC rounds contributions UP).
    def ceil_rupee(value)
      d(value).ceil(0)
    end

    # Paise precision (earnings proration).
    def round2(value)
      d(value).round(2)
    end

    # Section 288B: annual tax to the nearest ten rupees.
    def round_to_10(value)
      (d(value) / 10).round(0, BigDecimal::ROUND_HALF_UP) * 10
    end
  end
end
