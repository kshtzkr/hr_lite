module HrLite
  # Monthly run lifecycle: draft -> processing -> review -> finalized ->
  # published (terminal). Compute is synchronous (pure-Ruby math over a
  # small team; the seam for a background job is one perform_later away).
  class PayrollRun < ApplicationRecord
    STATUSES = %w[draft processing review finalized published].freeze

    has_many :salary_slips, dependent: :destroy
    belongs_to :created_by, class_name: HrLite.config.user_class, optional: true
    belongs_to :finalized_by, class_name: HrLite.config.user_class, optional: true
    belongs_to :published_by, class_name: HrLite.config.user_class, optional: true

    validates :period_month, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validate :period_is_first_of_month
    before_destroy :draft_only_destroy

    scope :recent_first, -> { order(period_month: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def editable?
      draft? || processing? || review?
    end

    def label
      period_month.strftime("%B %Y")
    end

    def compute!(actor:)
      raise_unless %w[draft review]

      update!(status: "processing")
      PayrollRunProcessor.call(self)
      update!(status: "review", processed_at: Time.current)
      true
    rescue => e
      update_columns(status: "draft") # rubocop:disable Rails/SkipsModelValidations
      raise e
    end

    def finalize!(actor:)
      raise_unless %w[review]
      raise ActiveRecord::RecordInvalid.new(self), "no slips" if salary_slips.none?

      update!(status: "finalized", finalized_at: Time.current, finalized_by_id: actor.id)
      Notifications.publish(
        "payroll.finalized",
        title: "Payroll #{label} finalized — #{salary_slips.count} slips, net #{Money.round2(total_net).to_s('F')}",
        path: "/admin/payroll_runs/#{id}"
      )
      true
    end

    def unlock!(actor:)
      raise_unless %w[finalized]
      update!(status: "review")
      true
    end

    def publish!(actor:)
      raise_unless %w[finalized]
      update!(status: "published", published_at: Time.current, published_by_id: actor.id)

      slips = salary_slips.includes(:user).to_a
      Notifications.publish(
        "payroll.published",
        title: "Your salary slip for #{label} is ready",
        body: "Open Earthly HR to view or download it.",
        path: "/salary_slips",
        bell_to: slips.map(&:user),
        email_to: slips.map(&:user)
      )
      true
    end

    # Ruby-side aggregates (amounts are encrypted — no SQL sums).
    def total_gross = sum_slips(:gross_earnings)
    def total_deductions = sum_slips(:total_deductions)
    def total_net = sum_slips(:net_pay)

    def total_employer_cost
      salary_slips.sum(BigDecimal(0)) do |slip|
        slip.employer_costs_hash.values.sum(BigDecimal(0)) { |v| Money.d(v) }
      end
    end

    private

    def sum_slips(attribute)
      salary_slips.sum(BigDecimal(0)) { |slip| slip.public_send(attribute) || BigDecimal(0) }
    end

    def raise_unless(allowed)
      raise ActiveRecord::RecordInvalid.new(self), "invalid transition" unless allowed.include?(status)
    end

    def period_is_first_of_month
      return unless period_month
      return if period_month.day == 1

      errors.add(:period_month, "must be the 1st of a month")
    end

    def draft_only_destroy
      return if draft?

      errors.add(:base, "Only draft runs can be deleted")
      throw :abort
    end
  end
end
