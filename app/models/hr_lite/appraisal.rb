module HrLite
  # Individual performance review. Drafted and edited by leadership,
  # invisible to the employee until shared; sharing locks it permanently —
  # a shared review is a record, corrections go in the next appraisal.
  # A promotion outcome records a DesignationChange at share time.
  class Appraisal < ApplicationRecord
    include Audited

    OUTCOMES = %w[none increment promotion].freeze
    STATUSES = %w[draft shared].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :reviewer, class_name: HrLite.config.user_class
    has_one :designation_change, dependent: :nullify

    validates :period_start, :period_end, presence: true
    validates :rating, inclusion: { in: 1..5 }, allow_nil: true
    validates :outcome, inclusion: { in: OUTCOMES }
    validates :status, inclusion: { in: STATUSES }
    validates :effective_date, presence: true, unless: -> { outcome == "none" }
    validates :new_designation, presence: true, if: -> { outcome == "promotion" }
    validate :period_order
    validate :locked_after_share
    before_destroy :draft_only_destroy

    scope :shared, -> { where(status: "shared") }
    scope :recent_first, -> { order(period_end: :desc, id: :desc) }

    def draft? = status == "draft"
    def shared? = status == "shared"

    def share!(actor:)
      raise ActiveRecord::RecordInvalid.new(self), "already shared" unless draft?

      transaction do
        update!(status: "shared", shared_at: Time.current)
        record_promotion!(actor) if outcome == "promotion"
      end

      Notifications.publish(
        "appraisal.shared",
        title: "Your appraisal for #{period_label} has been shared",
        body: rating ? "Rating: #{rating}/5" : nil,
        path: "/appraisals/#{id}",
        bell_to: [ user ],
        email_to: [ user ]
      )
      true
    end

    def period_label
      "#{period_start.strftime('%b %Y')} – #{period_end.strftime('%b %Y')}"
    end

    private

    def record_promotion!(actor)
      DesignationChange.create!(
        user_id: user_id,
        to_designation: new_designation,
        effective_date: effective_date,
        note: "Promotion via appraisal #{period_label}",
        appraisal_id: id,
        created_by_id: actor.id
      )
    end

    def draft_only_destroy
      return if draft?

      errors.add(:base, "Shared appraisals are permanent records")
      throw :abort
    end

    def period_order
      return unless period_start && period_end

      errors.add(:period_end, "must be after the start") if period_end < period_start
    end

    def locked_after_share
      return if new_record? || draft?
      # The share! transition itself sets status/shared_at; any other change
      # to a shared appraisal is tampering.
      changed_keys = changes.keys - %w[status shared_at updated_at]
      errors.add(:base, "A shared appraisal cannot be edited") if changed_keys.any? && status_was == "shared"
    end
  end
end
