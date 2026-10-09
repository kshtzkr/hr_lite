module HrLite
  # Employee of the month, quarter or year. Leadership picks the winner; one
  # per period, editable (to correct the winner) but never deleted.
  class Award < ApplicationRecord
    include Audited

    KINDS = %w[month quarter year].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true

    validates :kind, inclusion: { in: KINDS }
    validates :period_start, :citation, presence: true
    validates :period_start, uniqueness: { scope: :kind, message: "already has a winner" }

    before_validation :normalise_period
    after_save_commit :notify, if: -> { saved_change_to_user_id? }

    scope :recent_first, -> { order(period_start: :desc, kind: :asc) }

    # The latest started award of each kind, month first.
    def self.current
      KINDS.filter_map { |kind| where(kind: kind, period_start: ..Date.current).order(period_start: :desc).first }
    end

    def title = "Employee of the #{kind}"

    def period_label
      case kind
      when "month" then period_start.strftime("%B %Y")
      when "quarter" then "Q#{(period_start.month - 1) / 3 + 1} #{period_start.year}"
      else period_start.year.to_s
      end
    end

    private

    def normalise_period
      return unless period_start

      self.period_start = { "month" => period_start.beginning_of_month, "quarter" => period_start.beginning_of_quarter,
                            "year" => period_start.beginning_of_year }.fetch(kind, period_start)
    end

    def notify
      Notifications.publish("award.won", title: "You are #{title} — #{period_label}", body: citation,
                                         path: "/timeline", bell_to: [ user ], email_to: [ user ])
    end
  end
end
