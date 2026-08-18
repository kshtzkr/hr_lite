module HrLite
  # An earning or deduction head. Data, so an install can add "Night shift
  # allowance" without a gem release — and so a payslip line says what it
  # was for instead of disappearing into "other".
  class SalaryComponent < ApplicationRecord
    include Audited

    KINDS = %w[earning deduction].freeze

    # Heads the structure itself owns. A line item may not use these — they
    # already have a column, and two sources for one number is how a payslip
    # stops adding up.
    STRUCTURAL_CODES = %w[basic hra special_allowance other_earnings].freeze

    has_many :payroll_line_items, class_name: "HrLite::PayrollLineItem",
                                  foreign_key: :component_id, dependent: :restrict_with_error

    validates :code, presence: true, uniqueness: { case_sensitive: false },
                     format: { with: /\A[a-z0-9_]+\z/, message: "is lowercase letters, numbers and underscores" }
    validates :label, presence: true
    validates :kind, inclusion: { in: KINDS }
    validate :code_is_not_a_structural_one, on: :create

    scope :active, -> { where(active: true) }
    scope :earnings, -> { where(kind: "earning") }
    scope :deductions, -> { where(kind: "deduction") }
    scope :ordered, -> { order(:position, :label) }

    KINDS.each { |k| define_method("#{k}?") { kind == k } }

    def self.seed_defaults!
      [
        { code: "bonus", label: "Bonus", prorated: false, position: 10 },
        { code: "incentive", label: "Incentive", prorated: false, position: 20 },
        { code: "arrears", label: "Arrears", prorated: false, position: 30 },
        { code: "lta", label: "Leave travel allowance", prorated: false, position: 40 },
        { code: "reimbursement", label: "Reimbursement", prorated: false, taxable: false,
          counts_for_esi: false, position: 50 },
        { code: "loan_repayment", label: "Loan repayment", kind: "deduction",
          prorated: false, taxable: false, counts_for_esi: false, position: 60 },
        { code: "other_deduction", label: "Other deduction", kind: "deduction",
          prorated: false, taxable: false, counts_for_esi: false, position: 70 }
      ].filter_map do |attributes|
        next if exists?(code: attributes[:code])

        create!(attributes)
        attributes[:code]
      end
    end

    private

    def code_is_not_a_structural_one
      return unless STRUCTURAL_CODES.include?(code.to_s)

      errors.add(:code, "is already a salary-structure field — pick another name")
    end
  end
end
