module HrLite
  # An insurance policy or other benefit the company provides. Employees can
  # finally see what they are covered for without emailing somebody.
  class Benefit < ApplicationRecord
    include EncryptedMoney
    include Audited

    KINDS = %w[health life accident other].freeze

    encrypted_money :coverage, :employer_premium, :employee_premium

    has_many :benefit_enrolments, class_name: "HrLite::BenefitEnrolment", dependent: :destroy
    has_many :enrolled_users, through: :benefit_enrolments, source: :user

    validates :name, presence: true
    validates :kind, inclusion: { in: KINDS }
    validate :expiry_is_after_the_start

    scope :active, -> { where(active: true) }
    scope :live_on, ->(date) {
      active.where("effective_from IS NULL OR effective_from <= ?", date)
            .where("expires_on IS NULL OR expires_on >= ?", date)
    }

    def expiring?(within: 30, on: Date.current)
      expires_on.present? && expires_on <= on + within && expires_on >= on
    end

    private

    def expiry_is_after_the_start
      return if effective_from.nil? || expires_on.nil? || expires_on >= effective_from

      errors.add(:expires_on, "must be on or after the start date")
    end
  end
end
