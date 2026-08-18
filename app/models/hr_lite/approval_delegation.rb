module HrLite
  # "I am away until the 14th — Priya decides for me." Delegation does not
  # move the approval; it lets somebody else answer it, and the row records
  # who actually did.
  class ApprovalDelegation < ApplicationRecord
    include Audited

    belongs_to :from_user, class_name: HrLite.config.user_class
    belongs_to :to_user, class_name: HrLite.config.user_class

    validates :starts_on, :ends_on, presence: true
    validate :ends_after_it_starts
    validate :not_to_themselves

    scope :live_on, ->(date) { where(starts_on: ..date).where(ends_on: date..) }

    # Who may answer on `user`'s behalf today, including a chain of two —
    # A delegates to B, B is also away and delegates to C. Capped at two
    # hops: past that it is quicker to reassign the flow than to follow it.
    def self.stand_ins_for(user_id, on: Date.current)
      first = live_on(on).where(from_user_id: user_id).pluck(:to_user_id)
      second = live_on(on).where(from_user_id: first).pluck(:to_user_id)
      (first + second - [ user_id ]).uniq
    end

    private

    def ends_after_it_starts
      return unless starts_on && ends_on

      errors.add(:ends_on, "must be on or after the start date") if ends_on < starts_on
    end

    def not_to_themselves
      errors.add(:to_user_id, "cannot be the person delegating") if from_user_id == to_user_id
    end
  end
end
