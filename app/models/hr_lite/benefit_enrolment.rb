module HrLite
  # Who is covered, from when. Dependants are a COUNT, not a list — names and
  # dates of birth of somebody's family are data this engine has no reason to
  # hold, and holding them would mean protecting them.
  class BenefitEnrolment < ApplicationRecord
    include Audited

    belongs_to :benefit, class_name: "HrLite::Benefit"
    belongs_to :user, class_name: HrLite.config.user_class

    validates :enrolled_on, presence: true
    validates :user_id, uniqueness: { scope: :benefit_id }
    validates :dependants, numericality: { greater_than_or_equal_to: 0 }
    validate :ended_after_it_started

    scope :live_on, ->(date) {
      where(enrolled_on: ..date).where("ended_on IS NULL OR ended_on >= ?", date)
    }

    def live?(on = Date.current) = enrolled_on <= on && (ended_on.nil? || ended_on >= on)

    private

    def ended_after_it_started
      return if ended_on.nil? || enrolled_on.nil? || ended_on >= enrolled_on

      errors.add(:ended_on, "must be on or after the enrolment date")
    end
  end
end
