module HrLite
  # Indian-system amount in words (crore/lakh/thousand). A PORO — not a view
  # helper — because the slip PDF template is rendered by HOST code
  # (config.render_pdf), where engine helper modules are not in scope.
  module AmountInWords
    ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen
              fifteen sixteen seventeen eighteen nineteen].freeze
    TENS = %w[zero ten twenty thirty forty fifty sixty seventy eighty ninety].freeze
    SCALES = [ [ 10_000_000, "crore" ], [ 100_000, "lakh" ], [ 1000, "thousand" ], [ 100, "hundred" ] ].freeze

    module_function

    def words(amount)
      rupees = Money.round_rupee(amount).to_i
      return "Zero rupees" if rupees.zero?

      parts = []
      SCALES.each do |divisor, label|
        next unless rupees >= divisor

        parts << "#{two_digit(rupees / divisor)} #{label}"
        rupees %= divisor
      end
      parts << two_digit(rupees) if rupees.positive?
      "#{parts.join(' ').capitalize} rupees"
    end

    def two_digit(number)
      return ONES[number] if number < 20

      [ TENS[number / 10], number % 10 == 0 ? nil : ONES[number % 10] ].compact.join("-")
    end
  end
end
