module HrLite
  # Versioned by effective_from (always the 1st — mid-month revisions and
  # their blended-rate complexity are deliberately unsupported). Structures
  # are never destroyed; a new revision supersedes. Slips snapshot every
  # computed number, so editing a structure cannot corrupt history.
  class SalaryStructure < ApplicationRecord
    include EncryptedMoney
    include Audited

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    encrypted_money :basic, :hra, :special_allowance, :other_earnings

    validates :effective_from, presence: true, uniqueness: { scope: :user_id }
    validates :basic, presence: true
    validate :basic_positive
    validate :effective_from_is_first_of_month
    validates :pt_state, presence: true

    def self.effective_for(user, period_month)
      where(user_id: user.id)
        .where(effective_from: ..period_month.beginning_of_month)
        .order(effective_from: :desc)
        .first
    end

    def monthly_gross
      [ basic, hra, special_allowance, other_earnings ].compact.sum(BigDecimal(0))
    end

    def annual_gross
      monthly_gross * 12
    end

    private

    def basic_positive
      errors.add(:basic, "must be greater than zero") if basic && basic <= 0
    end

    def effective_from_is_first_of_month
      return unless effective_from
      return if effective_from.day == 1

      errors.add(:effective_from, "must be the 1st of a month")
    end
  end
end
