module HrLite
  # (Re)computes every slip for a run in one transaction. Missing structures
  # become warnings, manual overrides survive recomputes, employees who
  # became ineligible lose their draft slips.
  class PayrollRunProcessor
    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
    end

    def call
      # First in the list on purpose: if the statutory card is from an older
      # financial year, every number below it is computed on last year's
      # rates and that is the thing to read first.
      warnings = Array(StatutoryRateCard.warning_for(@run.period_month))
      warnings.concat(Array(StatutoryRateCard.unverified_for(@run.period_month)))

      ActiveRecord::Base.transaction do
        eligible = EmployeeProfile.active_for(@run.period_month).includes(:user).to_a
        keep_ids = []
        unconfigured_states = []

        eligible.each do |profile|
          user = profile.user
          structure = SalaryStructure.effective_for(user, @run.period_month)
          if structure.nil?
            warnings << "No salary structure for #{HrLite.display_name(user)} — skipped"
            next
          end

          # Professional tax is a state levy, and a state nobody has entered
          # slabs for deducts nothing — which looks exactly like a state that
          # levies nothing. Collected per state rather than per employee so a
          # forty-person office is one line, not forty.
          if Calculators::ProfessionalTax.unconfigured?(structure.pt_state, @run.period_month)
            unconfigured_states << structure.pt_state
          end

          slip = @run.salary_slips.find_or_initialize_by(user_id: user.id)
          attributes = SlipBuilder.call(
            run: @run, user: user, structure: structure, profile: profile,
            lop_override: slip.lop_override, tds_override: slip.tds_override
          )
          if attributes[:total_deductions] > attributes[:gross_earnings]
            warnings << "Deductions exceed earnings for #{HrLite.display_name(user)} — " \
                        "net pay floored at zero, review the overrides"
          end

          slip.assign_attributes(attributes)
          slip.save!
          keep_ids << slip.id
        end

        unconfigured_states.uniq.sort.each do |state|
          warnings << "No professional-tax slabs are configured for " \
                      "#{state.to_s.humanize} — everybody there is being deducted ₹0. " \
                      "Enter that state's bands, or set their structures to 'none' if " \
                      "it genuinely levies no PT."
        end

        @run.salary_slips.where.not(id: keep_ids).destroy_all
        @run.update!(warnings: warnings)
      end

      @run
    end
  end
end
