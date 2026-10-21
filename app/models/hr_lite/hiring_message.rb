module HrLite
  # One template sent (or being sent) to one candidate. The unique index on
  # candidate + template is what makes a repeated click or job a no-op.
  # "sending" left behind by a crash, and "unknown", both mean: look in Gmail.
  class HiringMessage < ApplicationRecord
    STATUSES = %w[queued sending sent failed unknown].freeze

    belongs_to :candidate, class_name: "HrLite::HiringCandidate"
    belongs_to :template, class_name: "HrLite::HiringTemplate"
    belongs_to :sent_by, class_name: HrLite.config.user_class, optional: true

    validates :status, inclusion: { in: STATUSES }
  end
end
