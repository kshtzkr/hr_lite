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

    encrypted_money :basic, :hra, :special_allowance, :other_earnings, :annual_ctc

    # Gratuity accrues at 15/26 days of Basic a year (4.81%), inside the CTC.
    GRATUITY_RATE = BigDecimal("0.0481")

    # The CTC is the input: saving one splits it, so no line is typed by hand.
    before_validation :fill_from_ctc, if: -> { annual_ctc.present? }
    # The admin form saves in this context: people only ever type the CTC.
    validates :annual_ctc, presence: true, on: :ctc_form

    validates :effective_from, presence: true, uniqueness: { scope: :user_id }
    validates :basic, presence: true
    validate :basic_positive
    validate :effective_from_is_first_of_month
    validates :pt_state, presence: true
    validate { errors.add(:base, "CTC is too low for this split") if special_allowance&.negative? }

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

    # A month of this structure: earnings, the employee's statutory
    # deductions and the employer's contributions, via the payroll calculators.
    def breakup(on: Date.current)
      month = on.beginning_of_month
      rates = StatutoryRateCard.for(month)
      gross = monthly_gross
      pf = Calculators::Pf.call(basic_earned: basic, on_full_basic: pf_on_full_basic, rates: rates[:pf]) if pf_applicable
      esi = Calculators::Esi.call(monthly_gross: esi_reference_gross(month), gross_earned: gross, applicable: esi_applicable, rates: rates[:esi])
      # Not flat: some states top up February, so the year is summed month by month.
      pts = (0..11).map { |i| Calculators::ProfessionalTax.call(state: pt_state, gross_earned: gross, period_month: month >> i, rates: rates[:pt]) }
      earnings, deductions, employer = [
        { "Basic" => basic, "HRA" => hra, "Special allowance" => special_allowance, "Other" => other_earnings },
        { "PF" => pf&.employee, "ESI" => esi.employee, "Professional tax" => pts.first },
        { "PF" => pf && (pf.employer_eps + pf.employer_epf), "ESI" => esi.employer, "Gratuity" => gratuity }
      ].map { |rows| rows.select { |_, amount| Money.d(amount).positive? } }
      monthly_ctc = gross + employer.values.sum(BigDecimal(0))
      in_hand = gross - deductions.values.sum(BigDecimal(0))
      { earnings: earnings, deductions: deductions, employer: employer,
        monthly_gross: gross, monthly_ctc: monthly_ctc, annual_ctc: monthly_ctc * 12, in_hand: in_hand,
        yearly: { "Professional tax" => pts.sum, "In-hand before tax" => (in_hand + pts.first) * 12 - pts.sum } }
    end

    # ESIC contribution periods run April–September and October–March.
    # Eligibility is fixed for the whole period, so it is decided on the
    # salary in force on its first day — re-deciding it every month dropped
    # someone out of ESI the moment a mid-period raise crossed the ceiling.
    def esi_reference_gross(month)
      start = if month.month.between?(4, 9)
        Date.new(month.year, 4, 1)
      elsif month.month >= 10
        Date.new(month.year, 10, 1)
      else
        Date.new(month.year - 1, 10, 1)
      end

      # Started mid-period: the structure in force when it opened decides (a mid-period joiner has none).
      earlier = self.class.effective_for(user, start) if effective_from&.after?(start)
      (earlier || self).monthly_gross
    end

    # Only a CTC-split structure carries gratuity in its CTC; older hand-typed
    # ones never did, and their CTC must not move.
    def gratuity
      Money.round_rupee(Money.d(basic) * GRATUITY_RATE) if annual_ctc.present? && basic
    end

    # Owner's split of annual_ctc (the labour codes' 50% wage floor): Basic 50%
    # of the monthly CTC, HRA 50% of Basic in a metro and 40% elsewhere,
    # employer PF, ESI and gratuity paid out of the CTC; Special takes the rest.
    def fill_from_ctc(on: effective_from || Date.current)
      monthly_ctc = Money.round_rupee(Money.d(annual_ctc) / 12)
      self.basic = Money.round_rupee(monthly_ctc / 2)
      self.hra = Money.round_rupee(basic * BigDecimal(metro ? "0.5" : "0.4"))
      self.other_earnings = nil
      self.special_allowance = 0
      rest = monthly_ctc - Money.d(breakup(on: on).dig(:employer, "PF")) - Money.d(gratuity)
      # Employer ESI is a share of the gross beside it: gross + ESI = rest.
      gross = (rest / (1 + StatutoryRateCard.for(on.beginning_of_month)[:esi][:employer_rate])).floor
      self.special_allowance = gross - basic - hra - Money.d(other_earnings)
      self.special_allowance += rest - gross unless breakup(on: on)[:employer].key?("ESI")
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
