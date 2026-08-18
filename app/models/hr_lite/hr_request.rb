module HrLite
  # "Can I have a salary certificate?" — the questions that were going to
  # somebody's inbox and getting lost there.
  class HrRequest < ApplicationRecord
    include Audited

    STATUSES = %w[open in_progress resolved closed cancelled].freeze

    CATEGORIES = %w[
      salary_certificate employment_certificate address_change bank_change
      document_request payroll_query tax_query insurance_query policy_query other
    ].freeze

    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :assigned_to, class_name: HrLite.config.user_class, optional: true

    validates :subject, presence: true
    validates :category, inclusion: { in: CATEGORIES }
    validates :status, inclusion: { in: STATUSES }

    scope :open_requests, -> { where(status: %w[open in_progress]) }
    scope :recent_first, -> { order(created_at: :desc) }

    STATUSES.each { |s| define_method("#{s}?") { status == s } }

    after_create_commit :notify_desk

    def category_label = category.humanize

    def assign!(actor:, assignee:)
      update!(assigned_to_id: assignee.id, status: "in_progress")
      Notifications.publish(
        "hr_request.assigned",
        title: "#{category_label}: #{subject}",
        body: "Assigned to you by #{HrLite.display_name(actor)}.",
        path: "/admin/hr_requests/#{id}", bell_to: [ assignee ]
      )
      true
    end

    def resolve!(actor:, resolution:)
      raise ArgumentError, "a resolution needs an answer" if resolution.blank?

      update!(status: "resolved", resolution: resolution, resolved_at: Time.current,
              assigned_to_id: assigned_to_id || actor.id)
      Notifications.publish(
        "hr_request.resolved",
        title: "Your request was answered — #{subject}",
        body: resolution, path: "/hr_requests/#{id}",
        bell_to: [ user ], email_to: [ user ]
      )
      true
    end

    def cancel!(actor:)
      raise ActiveRecord::RecordInvalid.new(self), "already settled" unless open? || in_progress?

      update!(status: "cancelled")
      true
    end

    private

    def notify_desk
      desk = HrLite.users_holding("hr_request.manage").to_a
      return if desk.empty?

      Notifications.publish(
        "hr_request.raised",
        title: "#{HrLite.display_name(user)} asked: #{subject}",
        body: body.presence, path: "/admin/hr_requests/#{id}", bell_to: desk
      )
    end
  end
end
