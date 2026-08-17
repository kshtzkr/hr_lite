# TEST-ONLY bridge from the pre-0.6.0 access idiom to roles.
#
# Most of this suite grants access the way hosts used to: by setting
# `HrLite.config.leadership_emails` or building a user with the `:admin`
# trait. Roles replaced that, and rewriting six hundred examples to assign
# roles by hand would have thrown away what those examples are actually
# worth — they assert behaviour, not mechanism.
#
# So the same mapping the upgrade migration performs is applied here, lazily,
# for a user who holds no roles yet. Every one of those examples now proves
# that a person who could reach something through the email lists reaches
# exactly the same thing through roles. That is the migration's contract,
# tested six hundred times over.
#
# It lives in spec/support and prepends onto the resolver, so the shipped
# code is not aware of it and production stays strict: no roles, no access.
module LegacyTierBridge
  # Examples that test the roles machinery ITSELF — the upgrade migration
  # above all — have to see the real thing, with no fixture quietly handing
  # people roles behind them. Tag them `no_legacy_bridge: true`.
  class << self
    attr_accessor :disabled
  end

  def resolve(user)
    resolved = super
    return resolved if LegacyTierBridge.disabled || resolved.any? || user.id.nil?

    names = legacy_role_names(user)
    return resolved if names.empty?

    HrLite::RoleSeeds.call
    rows = HrLite::Role.where(name: names).map do |role|
      { user_id: user.id, role_id: role.id, created_at: Time.current, updated_at: Time.current }
    end
    # insert_all, not create!: a real assignment is audited and bells
    # leadership, and this back-fill is a test fixture standing in for
    # something the host did before the upgrade. Auditing it would put rows
    # and emails into examples that are counting their own.
    HrLite::RoleAssignment.insert_all(rows) if rows.any?
    super
  end

  private

  def legacy_role_names(user)
    address = user.respond_to?(:email) ? user.email.to_s.downcase.strip : ""
    leaders = HrLite.normalize_email_list(HrLite.config.leadership_emails)
    money = HrLite.normalize_email_list(HrLite.config.superadmin_emails)
    money = leaders if money.empty?

    names = [ HrLite::Role::EMPLOYEE ]
    names << HrLite::Role::SUPER_ADMIN if address.present? && money.include?(address)
    names << HrLite::Role::LEADERSHIP if address.present? && leaders.include?(address)
    names << HrLite::Role::HR if legacy_admin?(user)
    names
  end

  def legacy_admin?(user)
    !!HrLite.config.admin_check.call(user)
  rescue StandardError
    false
  end
end

HrLite::Access.singleton_class.prepend(LegacyTierBridge)

# The fan-out queries ("who are the admins?") read the grant tables directly
# rather than resolving one user at a time, so the lazy bridge above would
# never have fired for somebody nobody had looked at yet. Warm every employee
# first — this is the test bridge paying for its own laziness.
module LegacyFanoutBridge
  def users_holding(key, scope: :all)
    return super if LegacyTierBridge.disabled

    config.employees_scope.call.find_each { |user| HrLite::Access.for(user) }
    HrLite::Current.access_cache = nil
    super
  end
end

HrLite.singleton_class.prepend(LegacyFanoutBridge)

# Assigning roles directly, for the examples that test roles themselves.
module RoleHelpers
  def grant_role(user, name, granted_by: nil)
    HrLite::RoleSeeds.call
    role = HrLite::Role.find_by!(name: name)
    HrLite::RoleAssignment.find_or_create_by!(user_id: user.id, role: role) do |assignment|
      assignment.granted_by_id = granted_by&.id
    end
    HrLite::Current.access_cache = nil
    role
  end

  # A user with exactly these roles and nothing the bridge would add.
  def user_with_roles(*names, **attributes)
    user = create(:user, **attributes)
    names.each { |name| grant_role(user, name) }
    user
  end
end

RSpec.configure do |config|
  config.include RoleHelpers
  # CurrentAttributes are reset between requests in production; between
  # examples, that is this hook's job.
  config.before(:each) do |example|
    HrLite::Current.access_cache = nil
    LegacyTierBridge.disabled = !!example.metadata[:no_legacy_bridge]
  end
  config.after(:each) { LegacyTierBridge.disabled = false }
end
