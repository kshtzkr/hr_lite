module HrLite
  # One interview round on the sender's Google Calendar. A new round is a new
  # row, so earlier rounds keep their own history.
  class HiringInterview < ApplicationRecord
    STATUSES = %w[unknown scheduled failed cancelled].freeze

    belongs_to :candidate, class_name: "HrLite::HiringCandidate"

    validates :status, inclusion: { in: STATUSES }
    validates :round, numericality: { greater_than: 0 }
    validates :starts_at, :ends_at, presence: true
  end
end
