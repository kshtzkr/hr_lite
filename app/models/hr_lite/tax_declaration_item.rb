module HrLite
  # One line of a declaration: "80C — ELSS — ₹1,50,000".
  #
  # `verified_amount` is what the proof actually supported, which is often
  # less than what was claimed and is the number payroll uses once HR has
  # looked. Both are encrypted: what somebody invests is their business.
  class TaxDeclarationItem < ApplicationRecord
    include EncryptedMoney

    SECTIONS = %w[80c 80d 80ccd_1b 24b hra other].freeze

    encrypted_money :declared_amount, :verified_amount

    belongs_to :declaration, class_name: "HrLite::TaxDeclaration"

    validates :section, inclusion: { in: SECTIONS }
    validate :amounts_are_not_negative

    def section_label
      { "80c" => "80C — investments", "80d" => "80D — health insurance",
        "80ccd_1b" => "80CCD(1B) — NPS", "24b" => "24(b) — home loan interest",
        "hra" => "HRA exemption", "other" => "Other" }.fetch(section, section)
    end

    private

    def amounts_are_not_negative
      errors.add(:declared_amount, "cannot be negative") if declared_amount&.negative?
      errors.add(:verified_amount, "cannot be negative") if verified_amount&.negative?
    end
  end
end
