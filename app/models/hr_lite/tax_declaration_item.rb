module HrLite
  # One line of a declaration: "80C — ELSS — ₹1,50,000".
  #
  # `verified_amount` is what the proof actually supported, which is often
  # less than what was claimed and is the number payroll uses once HR has
  # looked. Both are encrypted: what somebody invests is their business.
  # The legal limit is applied on top, so nobody's arithmetic decides it.
  class TaxDeclarationItem < ApplicationRecord
    include EncryptedMoney

    SECTIONS = %w[80c 80ccd_1b 80d 80d_parents 24b hra other].freeze

    # Annual limits (old regime). 80D doubles for a senior; HRA is computed
    # from rent; "other" has no single limit.
    CAPS = { "80c" => 150_000, "80ccd_1b" => 50_000, "24b" => 200_000,
             "80d" => 25_000, "80d_parents" => 25_000 }.freeze
    SENIOR_80D_CAP = 50_000
    RENT_NEEDS_LANDLORD_PAN = 100_000
    PROOF_TYPES = %w[application/pdf image/jpeg image/png].freeze
    PROOF_MAX_BYTES = 5.megabytes

    encrypted_money :declared_amount, :verified_amount
    encrypts :landlord_pan
    normalizes :landlord_pan, with: ->(pan) { pan.to_s.strip.upcase.presence }

    belongs_to :declaration, class_name: "HrLite::TaxDeclaration"
    has_many_attached :proofs

    validates :section, inclusion: { in: SECTIONS }
    validate :amounts_are_not_negative
    validate :landlord_pan_for_large_rent
    validate :proofs_are_documents

    # Labels name the Income-tax Act 2025 section with the 1961 one people know.
    def section_label
      { "80c" => "Sec 123 (old 80C) — PF, PPF, ELSS, LIC, tuition fees, home-loan principal",
        "80ccd_1b" => "Sec 124 (old 80CCD(1B)) — your own extra NPS",
        "80d" => "Sec 126 (old 80D) — health insurance for you and family",
        "80d_parents" => "Sec 126 (old 80D) — health insurance for parents",
        "24b" => "Home-loan interest (old 24(b))",
        "hra" => "Rent paid in the year (for the HRA exemption)",
        "other" => "Other deductions" }.fetch(section, section)
    end

    def cap
      return SENIOR_80D_CAP if senior && section.start_with?("80d")

      CAPS[section]
    end

    # What payroll counts for this line: the claim until HR has checked the
    # proof, then what the proof supported — never above the legal limit.
    def allowed(verified:)
      base = verified ? Money.d(verified_amount) : Money.d(declared_amount)
      cap ? [ base, BigDecimal(cap) ].min : base
    end

    private

    def amounts_are_not_negative
      errors.add(:declared_amount, "cannot be negative") if declared_amount&.negative?
      errors.add(:verified_amount, "cannot be negative") if verified_amount&.negative?
    end

    def landlord_pan_for_large_rent
      return unless section == "hra" && Money.d(declared_amount) > RENT_NEEDS_LANDLORD_PAN

      if landlord_pan.blank?
        errors.add(:landlord_pan, "is needed when rent is above ₹1,00,000 a year")
      elsif !landlord_pan.match?(/\A[A-Z]{5}[0-9]{4}[A-Z]\z/)
        errors.add(:landlord_pan, "is not a valid PAN (like ABCDE1234F)")
      end
    end

    def proofs_are_documents
      proofs.each do |proof|
        next if PROOF_TYPES.include?(proof.blob.content_type) && proof.blob.byte_size <= PROOF_MAX_BYTES

        errors.add(:proofs, "must be PDF, JPG or PNG files of up to 5 MB")
        break
      end
    end
  end
end
