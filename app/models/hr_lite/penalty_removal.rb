module HrLite
  # HR took hours off a person's penalty total, with a reason; the rest stays.
  # Append-only, so every settlement stays on the person's record.
  class PenaltyRemoval < ApplicationRecord
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :removed_by, class_name: HrLite.config.user_class

    validates :minutes, numericality: { only_integer: true, greater_than: 0 }
    validates :reason, presence: true

    def readonly? = persisted?
  end
end
