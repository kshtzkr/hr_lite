module HrLite
  # One month's deduction actually taken. Written when the run is finalized,
  # so recomputing a draft never books a repayment twice — and the unique
  # index on [loan, month] means a retry cannot either.
  class LoanRepayment < ApplicationRecord
    include EncryptedMoney

    encrypted_money :amount

    belongs_to :loan, class_name: "HrLite::Loan"

    validates :period_month, presence: true, uniqueness: { scope: :loan_id }
  end
end
