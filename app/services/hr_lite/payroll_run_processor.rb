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
      warnings = []

      ActiveRecord::Base.transaction do
        eligible = EmployeeProfile.active_for(@run.period_month).includes(:user).to_a
        keep_ids = []

        eligible.each do |profile|
          user = profile.user
          structure = SalaryStructure.effective_for(user, @run.period_month)
          if structure.nil?
            warnings << "No salary structure for #{HrLite.display_name(user)} — skipped"
            next
          end

          slip = @run.salary_slips.find_or_initialize_by(user_id: user.id)
          attributes = SlipBuilder.call(
            run: @run, user: user, structure: structure, profile: profile,
            lop_override: slip.lop_override, tds_override: slip.tds_override
          )
          slip.assign_attributes(attributes)
          slip.save!
          keep_ids << slip.id
        end

        @run.salary_slips.where.not(id: keep_ids).destroy_all
        @run.update!(warnings: warnings)
      end

      @run
    end
  end
end
