module HrLite
  # A named bundle of grants. Roles are DATA — the seeded six are a starting
  # point an install is expected to edit, not a fixed ladder in code.
  class Role < ApplicationRecord
    include Audited

    # Seeded by name. `Employee` in particular is load-bearing: it is what a
    # new hire is given so that self-service works on day one.
    EMPLOYEE = "Employee".freeze
    MANAGER = "Manager".freeze
    HR = "HR".freeze
    FINANCE = "Finance".freeze
    LEADERSHIP = "Leadership".freeze
    SUPER_ADMIN = "Super Admin".freeze

    has_many :role_grants, dependent: :destroy
    has_many :role_assignments, dependent: :destroy

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    before_destroy :protect_system_role
    validate :system_role_keeps_its_name, on: :update

    scope :alphabetical, -> { order(:name) }

    # Every key this role grants, mapped to its scope. The shape the access
    # resolver merges.
    def grant_map
      role_grants.to_h { |grant| [ grant.permission_key, grant.scope ] }
    end

    # Replaces the whole grant set in one transaction — the roles screen posts
    # the complete picture, so a permission absent from the form is a
    # permission being taken away, not one left alone.
    def replace_grants!(grants)
      transaction do
        role_grants.destroy_all
        grants.each do |key, scope|
          next if scope.blank? || scope.to_s == "none"

          role_grants.create!(permission_key: Permissions.validate!(key), scope: scope.to_s)
        end
      end
      reload
    end

    def system? = self[:system]

    private

    def protect_system_role
      return unless system?

      errors.add(:base, "#{name} is a built-in role and cannot be deleted")
      throw :abort
    end

    # The name is the identifier the seed, the upgrade path and the specs all
    # use. Permissions on a system role are free to change; what it is called
    # is not.
    def system_role_keeps_its_name
      return unless system? && name_changed?

      errors.add(:name, "cannot be changed on a built-in role")
    end
  end
end
