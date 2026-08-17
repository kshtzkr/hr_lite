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
    # Create-only: an existing run must stay transitionable forever.
    validate :period_is_a_closed_month, on: :create
    before_destroy :draft_only_destroy

    scope :recent_first, -> { order(period_month: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    def editable?
      draft? || processing? || review?
    end

    def label
      period_month.strftime("%B %Y")
    end

    # `processing` is allowed back in so a run stranded there by a killed
    # process (deploy roll, timeout) can be recomputed instead of blocking
    # that month forever.
    def compute!(actor:)
      raise_unless %w[draft review processing]
      previous = status

      begin
        update!(status: "processing")
        PayrollRunProcessor.call(self)
        transaction do
          update!(status: "review", processed_at: Time.current)
          audit!("payroll.computed", actor,
                 "slips" => salary_slips.count, "warnings" => warnings.length,
                 "from_status" => previous)
        end
        true
      rescue => e
        # Restore what the run WAS. Hardcoding "draft" here used to demote a
        # finalized or published run — which then exposed the delete-draft
        # control, and that cascades over every salary slip.
        update_columns(status: previous) # rubocop:disable Rails/SkipsModelValidations
        raise e
      end
    end

    def finalize!(actor:)
      raise_unless %w[review]
      raise ActiveRecord::RecordInvalid.new(self), "no slips" if salary_slips.none?

      transaction do
        update!(status: "finalized", finalized_at: Time.current, finalized_by_id: actor.id)
        # Finalizing freezes every slip in the run. Who did it, to how many
        # people, is the row an investigation starts from.
        audit!("payroll.finalized", actor, "slips" => salary_slips.count)
      end
      Notifications.publish(
        "payroll.finalized",
        title: "Payroll #{label} finalized — #{salary_slips.count} slips, net #{Money.round2(total_net).to_s('F')}",
        path: "/admin/payroll_runs/#{id}"
      )
      true
    end

    def unlock!(actor:)
      raise_unless %w[finalized]
      transaction do
        update!(status: "review")
        # Reopening frozen slips for editing is the single most sensitive
        # transition in the module — it is the one that has to leave a trace.
        audit!("payroll.unlocked", actor, "slips" => salary_slips.count)
      end
      true
    end

    def publish!(actor:)
      raise_unless %w[finalized]
      transaction do
        update!(status: "published", published_at: Time.current, published_by_id: actor.id)
        audit!("payroll.published", actor, "slips" => salary_slips.count)
      end

      slips = salary_slips.includes(:user).to_a
      # Everyone is emailed — a final settlement matters most to the person who
      # has left — but a bell is only useful to someone who can still sign in,
      # and offboarding revokes that. Sending one pointed at a page they cannot
      # open is just noise in a place they will never look.
      exited = EmployeeProfile.where(user_id: slips.map(&:user_id))
                              .where(date_of_exit: ..Date.current)
                              .pluck(:user_id).to_set

      Notifications.publish(
        "payroll.published",
        title: "Your salary slip for #{label} is ready",
        body: "Open Earthly HR to view or download it.",
        path: "/salary_slips",
        bell_to: slips.reject { |slip| exited.include?(slip.user_id) }.map(&:user),
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

    # Amounts stay out of it on purpose: audit_logs is a plaintext table and
    # every slip amount in this module is encrypted. The row records WHO
    # moved the run and HOW FAR, never what anyone is paid.
    def audit!(action, actor, changes)
      AuditLog.record!(action: action, subject: self, actor: actor,
                       changes: changes.merge("period" => label))
    end

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

    # Days that have not happened yet score as `upcoming`, which payroll folds
    # into payable — so computing a month before it ends pays for days nobody
    # worked, and once finalized the slips are immutable.
    def period_is_a_closed_month
      return unless period_month
      return if period_month.end_of_month < Date.current

      errors.add(:period_month, "must be a month that has already ended")
    end

    def draft_only_destroy
      return if draft?

      errors.add(:base, "Only draft runs can be deleted")
      throw :abort
    end
  end
end
