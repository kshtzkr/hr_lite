module HrLite
  # Engine-owned singleton settings row.
  class Setting < ApplicationRecord
    include Audited

    WEEKEND_POLICIES = %w[sun_only sat_sun second_fourth_sat_sun].freeze

    validates :weekend_policy, inclusion: { in: WEEKEND_POLICIES }

    def self.instance
      first_or_create!
    end

    private

    # The defaults row bootstraps itself on first read — a system action,
    # not a governing change; auditing it would email leadership noise.
    # Real edits (updates) stay fully audited.
    def hr_lite_audit!(action)
      return if action == "create" && HrLite::Current.actor.nil?

      super
    end
  end
end
