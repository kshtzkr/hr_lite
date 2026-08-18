module HrLite
  # Who had it, when, and what state it came back in. Append-only: editing an
  # assignment away is how a missing laptop stops being anybody's.
  class AssetAssignment < ApplicationRecord
    belongs_to :asset, class_name: "HrLite::Asset"
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :assigned_by, class_name: HrLite.config.user_class, optional: true

    validates :assigned_on, presence: true
    validate :returned_after_it_was_given

    scope :live, -> { where(returned_on: nil) }

    def live? = returned_on.nil?

    private

    def returned_after_it_was_given
      return if returned_on.nil? || assigned_on.nil? || returned_on >= assigned_on

      errors.add(:returned_on, "cannot be before the day it was handed over")
    end
  end
end
