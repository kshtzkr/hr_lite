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

    # Indian digit grouping: 12,34,567 — not the western 1,234,567. It lives
    # here rather than only in the view helper because the slip PDF is
    # rendered by HOST code (config.render_pdf), where engine helpers are out
    # of scope — which is why the PDF printed a bare "75000.0" next to the
    # web slip's "₹75,000.00".
    def format(amount)
      return "—" if amount.nil?

      whole, fraction = round2(amount).to_s("F").split(".")
      sign = whole.start_with?("-") ? "-" : ""
      whole = whole.delete_prefix("-")
      if whole.length > 3
        head = whole[0..-4].reverse.scan(/\d{1,2}/).join(",").reverse
        whole = "#{head},#{whole[-3..]}"
      end
      "#{sign}#{HrLite.config.currency_symbol}#{whole}.#{fraction.ljust(2, '0')}"
    end
  end
end
