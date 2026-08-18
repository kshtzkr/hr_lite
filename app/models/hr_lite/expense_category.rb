module HrLite
  # "Travel", "Client entertainment", "Home office" — with the cap and the
  # receipt rule that go with each.
  class ExpenseCategory < ApplicationRecord
    include EncryptedMoney
    include Audited

    encrypted_money :monthly_cap

    has_many :expenses, class_name: "HrLite::Expense", foreign_key: :category_id,
                        dependent: :restrict_with_error

    validates :name, presence: true, uniqueness: { case_sensitive: false }

    scope :active, -> { where(active: true) }
    scope :alphabetical, -> { order(:name) }

    def uncapped? = monthly_cap.nil?

    # What is left of this month's cap for one person, or nil when uncapped.
    # Counts everything not refused: a claim awaiting a decision has still
    # been spent against the cap.
    def remaining_for(user, month = Date.current.beginning_of_month)
      return nil if uncapped?

      spent = expenses.where(user_id: user.id)
                      .where(spent_on: month..month.end_of_month)
                      .where.not(status: %w[rejected cancelled])
                      .sum(BigDecimal(0)) { |e| e.amount || BigDecimal(0) }
      [ monthly_cap - spent, BigDecimal(0) ].max
    end
  end
end
