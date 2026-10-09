module HrLite
  # A chartered accountant's year-end mark on one salary slip or tax
  # declaration. Verifying is final; a flag says what is wrong and stays open
  # until HR or payroll fixes it the normal way (a correcting line on a later
  # slip, or reopening the declaration) and resolves it. The slip itself is
  # never edited.
  class CaReview < ApplicationRecord
    include Audited

    SUBJECTS = %w[HrLite::SalarySlip HrLite::TaxDeclaration].freeze
    STATUSES = %w[verified flagged resolved].freeze

    belongs_to :subject, polymorphic: true
    belongs_to :reviewed_by, class_name: HrLite.config.user_class
    belongs_to :resolved_by, class_name: HrLite.config.user_class, optional: true

    validates :subject_type, inclusion: { in: SUBJECTS }
    validates :status, inclusion: { in: STATUSES }
    validates :note, presence: true, if: -> { status == "flagged" }

    # What the CA reviews for a financial year: every published slip, and
    # every declaration somebody actually filed.
    def self.slips_for(fy)
      SalarySlip.joins(:payroll_run).where(hr_lite_payroll_runs: { status: "published", period_month: fy...fy.next_year })
    end

    def self.declarations_for(fy) = TaxDeclaration.where(financial_year: fy).where.not(status: "draft")

    # Still to do before 31 March: never reviewed, or flagged and not resolved.
    def self.outstanding(fy)
      { "slips" => slips_for(fy), "declarations" => declarations_for(fy) }.transform_values do |scope|
        done = where(subject: scope, status: %w[verified resolved]).count
        scope.count - done
      end.merge("flagged" => where(subject_type: SUBJECTS, status: "flagged").count)
    end

    def self.verify!(subject, actor:)
      review = find_or_initialize_by(subject: subject)
      review.update!(status: "verified", note: nil, reviewed_by_id: actor.id, reviewed_at: Time.current)
      review
    end

    def self.flag!(subject, actor:, note:)
      review = find_or_initialize_by(subject: subject)
      review.update!(status: "flagged", note: note.to_s.strip, reviewed_by_id: actor.id, reviewed_at: Time.current,
                     resolved_by_id: nil, resolved_at: nil, resolution_note: nil)
      people = (HrLite.users_holding("payroll.approve", scope: :all).to_a | HrLite.users_holding("payroll.manage", scope: :all).to_a)
      Notifications.publish("ca.flagged", title: "CA flagged #{review.subject_label}", body: review.note,
                                          path: "/admin/ca_reviews?status=flagged", bell_to: people, email_to: people)
      review
    end

    def resolve!(actor:, note:)
      raise ActiveRecord::RecordInvalid.new(self), "not flagged" unless status == "flagged"

      update!(status: "resolved", resolved_by_id: actor.id, resolved_at: Time.current, resolution_note: note.to_s.strip.presence)
    end

    def subject_label
      case subject
      when SalarySlip then "#{HrLite.display_name(subject.user)}'s #{subject.period_month.strftime('%B %Y')} slip"
      else "#{HrLite.display_name(subject.user)}'s #{subject.label} tax declaration"
      end
    end
  end
end
