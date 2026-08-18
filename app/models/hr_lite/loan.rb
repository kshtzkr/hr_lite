module HrLite
  # A salary advance or loan, repaid by a fixed monthly deduction.
  #
  # The outstanding balance is DERIVED from the repayments actually taken,
  # never stored. A stored balance and a recomputed payroll run disagree the
  # first time somebody deletes a draft.
  class Loan < ApplicationRecord
    include EncryptedMoney
    include Audited

    STATUSES = %w[active closed cancelled].freeze

    encrypted_money :principal, :monthly_instalment

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :approved_by, class_name: HrLite.config.user_class, optional: true
    has_many :loan_repayments, class_name: "HrLite::LoanRepayment", dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates :starts_on, presence: true
    validate :amounts_are_positive
    validate :instalment_is_not_larger_than_the_loan

    scope :active, -> { where(status: "active") }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def repaid = loan_repayments.sum(BigDecimal(0)) { |r| r.amount || BigDecimal(0) }

    def outstanding = [ principal - repaid, BigDecimal(0) ].max

    # What to deduct this month: the instalment, or whatever is left if that
    # is less — the last instalment is almost never a round one.
    def instalment_for(period_month)
      return BigDecimal(0) unless active?
      return BigDecimal(0) if period_month < starts_on.beginning_of_month
      return BigDecimal(0) if loan_repayments.exists?(period_month: period_month)

      [ monthly_instalment, outstanding ].min
    end

    # Called after a run is FINALIZED, not at compute: a draft is recomputed
    # freely and each pass would otherwise book another repayment.
    def record_repayment!(period_month, amount)
      return if amount.nil? || amount <= 0

      loan_repayments.create!(period_month: period_month, amount: amount)
      update!(status: "closed") if outstanding.zero?
    end

    private

    def amounts_are_positive
      errors.add(:principal, "must be more than zero") unless principal&.positive?
      errors.add(:monthly_instalment, "must be more than zero") unless monthly_instalment&.positive?
    end

    def instalment_is_not_larger_than_the_loan
      return if principal.nil? || monthly_instalment.nil?
      return if monthly_instalment <= principal

      errors.add(:monthly_instalment, "cannot be more than the loan itself")
    end
  end
end
