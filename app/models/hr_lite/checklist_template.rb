module HrLite
  # "Collect the signed offer letter", "Revoke email access". The steps a
  # company means to take every time and forgets once.
  class ChecklistTemplate < ApplicationRecord
    include Audited

    KINDS = %w[onboarding offboarding].freeze

    validates :kind, inclusion: { in: KINDS }
    validates :title, presence: true
    validate :owner_permission_is_declared

    scope :active, -> { where(active: true) }
    scope :for_kind, ->(kind) { active.where(kind: kind.to_s).order(:position, :id) }

    def self.seed_defaults!
      [
        { kind: "onboarding", title: "Collect signed offer letter", position: 10,
          owner_permission: "document.manage" },
        { kind: "onboarding", title: "Collect PAN and Aadhaar", position: 20,
          owner_permission: "document.manage" },
        { kind: "onboarding", title: "Create payroll record and salary structure",
          position: 30, owner_permission: "salary.manage", due_offset_days: 3 },
        { kind: "onboarding", title: "Hand over laptop and access", position: 40,
          owner_permission: "profile.manage" },
        { kind: "offboarding", title: "Collect laptop and accessories", position: 10,
          owner_permission: "profile.manage" },
        { kind: "offboarding", title: "Revoke email and system access", position: 20,
          owner_permission: "profile.manage" },
        { kind: "offboarding", title: "Full and final settlement", position: 30,
          owner_permission: "payroll.manage", due_offset_days: 30 },
        { kind: "offboarding", title: "Issue relieving and experience letters",
          position: 40, owner_permission: "document.manage", due_offset_days: 7 }
      ].filter_map do |attributes|
        next if exists?(kind: attributes[:kind], title: attributes[:title])

        create!(attributes)
        "#{attributes[:kind]}: #{attributes[:title]}"
      end
    end

    private

    def owner_permission_is_declared
      return if owner_permission.blank? || Permissions.valid?(owner_permission)

      errors.add(:owner_permission, "is not a known permission")
    end
  end
end
