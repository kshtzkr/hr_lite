module HrLite
  # Money that must be encrypted at rest. Rails `encrypts` only works on
  # text columns, so amounts are stored as canonical decimal strings and
  # surfaced as BigDecimal. BigDecimal in, BigDecimal out; Float never.
  #
  # Accepted trade-off (documented): encrypted amounts cannot be aggregated
  # in SQL — all totals are computed in Ruby. Fine well past 100 employees.
  module EncryptedMoney
    extend ActiveSupport::Concern

    class_methods do
      def encrypted_money(*attributes)
        attributes.each do |attribute|
          encrypts attribute

          define_method(attribute) do
            raw = super()
            raw.nil? ? nil : BigDecimal(raw)
          end

          define_method("#{attribute}=") do |value|
            if value.nil? || (value.respond_to?(:blank?) && value.blank?)
              super(nil)
            else
              super(BigDecimal(value.to_s).round(2).to_s("F"))
            end
          end
        end
      end
    end
  end
end
