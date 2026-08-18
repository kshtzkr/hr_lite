module HrLite
  # A one-off on one month's payslip: a bonus, an incentive, arrears after a
  # backdated revision, a reimbursement, a one-time deduction.
  #
  # Dated to the MONTH, not to the run, so deleting a draft run and computing
  # it again does not lose them.
  class PayrollLineItem < ApplicationRecord
    include EncryptedMoney
    include Audited

    encrypted_money :amount

    belongs_to :component, class_name: "HrLite::SalaryComponent"
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    validates :period_month, presence: true
    validate :period_is_first_of_month
    validate :amount_is_positive
    validate :period_is_not_already_paid, on: :create

    scope :for_month, ->(month) { where(period_month: month) }

    def self.for_slip(user, period_month)
      where(user_id: user.id, period_month: period_month).includes(:component)
    end

    private

    def period_is_first_of_month
      return if period_month.nil? || period_month.day == 1

      errors.add(:period_month, "must be the 1st of a month")
    end

    # Amounts are signed by the component's KIND, not by the number: a
    # deduction of -500 and a deduction of 500 would otherwise both be
    # storable and mean opposite things.
    def amount_is_positive
      return if amount.nil? || amount.positive?

      errors.add(:amount, "must be more than zero — a deduction is a deduction by its component, not by a minus sign")
    end

    # A published slip is immutable. Adding a line to that month afterwards
    # would show on no payslip and quietly change the year-to-date totals the
    # TDS projector reads.
    def period_is_not_already_paid
      return if user_id.nil? || period_month.nil?

      settled = SalarySlip.settled.exists?(user_id: user_id, period_month: period_month)
      return unless settled

      errors.add(:period_month, "has already been paid — put this on the next open month")
    end
  end
end
