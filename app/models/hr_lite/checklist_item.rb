module HrLite
  # One step for one person. Kept even when its template is later deleted —
  # what a company DID on somebody's first day is history, and history should
  # not change because a template was tidied up.
  class ChecklistItem < ApplicationRecord
    include Audited

    belongs_to :template, class_name: "HrLite::ChecklistTemplate", optional: true
    belongs_to :user, class_name: HrLite.config.user_class
    belongs_to :completed_by, class_name: HrLite.config.user_class, optional: true

    validates :kind, inclusion: { in: ChecklistTemplate::KINDS }
    validates :title, presence: true

    scope :outstanding, -> { where(completed_at: nil) }
    scope :for_kind, ->(kind) { where(kind: kind.to_s) }
    scope :overdue, ->(on = Date.current) { outstanding.where(due_on: ...on) }

    def done? = completed_at.present?

    def overdue?(on = Date.current) = !done? && due_on.present? && due_on < on

    def complete!(actor:, note: nil)
      update!(completed_at: Time.current, completed_by_id: actor&.id, note: note.presence)
    end

    def reopen!(actor:)
      update!(completed_at: nil, completed_by_id: nil)
    end

    # Builds somebody's list from the active templates. Idempotent: running
    # it twice does not double the list, so a re-run after adding a template
    # adds only what is new.
    def self.open_for!(user, kind:, anchor_date:)
      ChecklistTemplate.for_kind(kind).filter_map do |template|
        next if exists?(user_id: user.id, kind: kind.to_s, title: template.title)

        create!(user_id: user.id, template: template, kind: kind.to_s, title: template.title,
                due_on: anchor_date + template.due_offset_days)
      end
    end
  end
end
