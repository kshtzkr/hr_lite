module HrLite
  module Calculators
    # Calendar-day proration: each structure component earns
    # full × payable/days_in_month, rounded to paise per line.
    module Proration
      COMPONENTS = [
        [ "basic", "Basic" ],
        [ "hra", "HRA" ],
        [ "special_allowance", "Special allowance" ],
        [ "other_earnings", "Other earnings" ]
      ].freeze

      def self.call(structure:, payable_days:, days_in_month:)
        factor = Money.d(payable_days) / Money.d(days_in_month)

        COMPONENTS.filter_map do |attribute, label|
          full = structure.public_send(attribute)
          next if full.nil? || full.zero?

          {
            code: attribute,
            label: label,
            full_amount: Money.round2(full),
            amount: Money.round2(full * factor)
          }
        end
      end
    end
  end
end
