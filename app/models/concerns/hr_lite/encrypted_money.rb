module HrLite
  # Money that must be encrypted at rest. Rails `encrypts` only works on
  # text columns, so amounts are stored as canonical decimal strings and
  # surfaced as BigDecimal. BigDecimal in, BigDecimal out; Float never.
  #
  # Accepted trade-off (documented): encrypted amounts cannot be aggregated
  # in SQL — all totals are computed in Ruby. Fine well past 100 employees.
  module EncryptedMoney
    extend ActiveSupport::Concern

    included do
      validate { @unreadable_money&.each { |attribute| errors.add(attribute, "is not a number") } }
    end

    class_methods do
      def encrypted_money(*attributes)
        attributes.each do |attribute|
          encrypts attribute

          define_method(attribute) do
            raw = super()
            raw.nil? ? nil : BigDecimal(raw)
          end

          define_method("#{attribute}=") do |value|
            digits = value.to_s.gsub(/[,₹\s]/, "") # "1,50,000" and "₹ 1200" are how people type money
            super(digits.empty? ? nil : BigDecimal(digits).round(2).to_s("F"))
          rescue ArgumentError
            (@unreadable_money ||= []) << attribute
          end
        end
      end
    end
  end
end
