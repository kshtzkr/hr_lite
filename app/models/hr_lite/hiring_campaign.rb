module HrLite
  # One hiring drive for one opening. Its fields fill the @placeholders in
  # every email, so the offer lives here, never in template copy.
  class HiringCampaign < ApplicationRecord
    has_many :candidates, class_name: "HrLite::HiringCandidate", foreign_key: :campaign_id,
                          inverse_of: :campaign, dependent: :restrict_with_error

    validates :title, :position, presence: true
    validates :status, inclusion: { in: %w[open closed] }

    scope :newest_first, -> { order(created_at: :desc) }

    # The pipeline list and "select all" on it are the same filter.
    def pipeline(stage: nil, campus: nil)
      scope = candidates
      scope = scope.where(stage: stage) if stage.presence_in(HiringCandidate::STAGES)
      scope = scope.where(campus: campus) if campus.present?
      scope.order(:name, :id)
    end
  end
end
