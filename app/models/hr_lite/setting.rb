module HrLite
  # Engine-owned singleton settings row.
  class Setting < ApplicationRecord
    include Audited

    WEEKEND_POLICIES = %w[sun_only sat_sun second_fourth_sat_sun].freeze

    validates :weekend_policy, inclusion: { in: WEEKEND_POLICIES }

    def self.instance
      first_or_create!
    end
  end
end
