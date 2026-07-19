module HrLite
  # One employee-month. All MONEY is snapshotted (encrypted JSON line items +
  # encrypted totals); identity numbers (PAN/UAN/bank) render live from the
  # profile — a typo fix must flow to old slips, and duplicating encrypted
  # PII per month multiplies liability. Visibility and immutability delegate
  # to the run's lifecycle.
  class SalarySlip < ApplicationRecord
    include EncryptedMoney

    belongs_to :payroll_run
    belongs_to :user, class_name: HrLite.config.user_class

    encrypts :earnings, :deductions, :employer_costs, :tax_details
    encrypted_money :tds_override, :gross_earnings, :total_deductions, :net_pay

    validates :period_month, presence: true, uniqueness: { scope: :user_id }
    validates :user_id, uniqueness: { scope: :payroll_run_id }
    before_save :ensure_run_editable

    scope :published, -> { joins(:payroll_run).where(hr_lite_payroll_runs: { status: "published" }) }
    scope :recent_first, -> { order(period_month: :desc) }

    def published?
      payroll_run.published?
    end

    def earnings_rows = parse_json(earnings)
    def deductions_rows = parse_json(deductions)
    def employer_costs_hash = parse_json(employer_costs, fallback: {})
    def tax_details_hash = parse_json(tax_details, fallback: {})

    def effective_lop_days
      lop_override || lop_days
    end

    # Indian FY (Apr 1) to-date sums of PUBLISHED slips before this period —
    # feeds the TDS projector and the slip's YTD table.
    def self.fy_to_date(user, period_month)
      fy_start = period_month.month >= 4 ? Date.new(period_month.year, 4, 1)
                                         : Date.new(period_month.year - 1, 4, 1)
      slips = published.where(user_id: user.id)
                       .where(period_month: fy_start...period_month)
      {
        gross: slips.sum(BigDecimal(0)) { |s| s.gross_earnings || BigDecimal(0) },
        tds: slips.sum(BigDecimal(0)) { |s| Money.d(s.deduction_amount("tds")) },
        months: slips.count
      }
    end

    def deduction_amount(code)
      row = deductions_rows.find { |r| r["code"] == code }
      row ? Money.d(row["amount"]) : BigDecimal(0)
    end

    def pdf_cache_key
      [ "hr_lite_slip", id, updated_at.to_i, payroll_run.status,
        user_profile&.updated_at.to_i ].join("/")
    end

    def user_profile
      @user_profile ||= EmployeeProfile.find_by(user_id: user_id)
    end

    private

    def parse_json(raw, fallback: [])
      raw.blank? ? fallback : JSON.parse(raw)
    end

    def ensure_run_editable
      return if payroll_run.nil? || payroll_run.editable?
      # The lifecycle transitions themselves touch only the run row, never
      # slip attributes — any slip write outside draft/processing/review is
      # a bug or tampering.
      raise ActiveRecord::ReadOnlyRecord, "slips are immutable once the run is finalized"
    end
  end
end
