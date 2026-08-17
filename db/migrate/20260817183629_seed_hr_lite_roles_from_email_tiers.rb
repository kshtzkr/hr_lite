class SeedHrLiteRolesFromEmailTiers < ActiveRecord::Migration[8.1]
  # The upgrade path off the email lists. On an install that is already
  # running, this is the migration that decides whether anyone loses access,
  # so it is deliberately generous: everybody who could reach something
  # before can reach at least as much afterwards.
  #
  #   config.superadmin_emails  -> Super Admin
  #   config.leadership_emails  -> Leadership
  #   admin_check == true       -> HR
  #   everybody else            -> Employee
  #
  # It reads the host's OWN configuration, so nothing has to be typed twice,
  # and it says out loud what it did — an upgrade that silently grants the
  # money tier to the wrong person is the failure worth being loud about.
  def up
    require "hr_lite/role_seeds"
    created = HrLite::RoleSeeds.call
    say "Seeded roles: #{created.join(', ')}" if created.any?

    # A host that has already assigned roles by hand is not re-derived from
    # email lists — that would undo their work.
    if HrLite::RoleAssignment.exists?
      say "Role assignments already exist — leaving them alone."
      return
    end

    roles = HrLite::Role.where(name: [
      HrLite::Role::EMPLOYEE, HrLite::Role::HR,
      HrLite::Role::LEADERSHIP, HrLite::Role::SUPER_ADMIN
    ]).index_by(&:name)

    # The legacy predicates, read directly rather than through HrLite.admin?
    # — which by now answers off roles, and would say no to everyone.
    superadmins = HrLite.normalize_email_list(HrLite.config.superadmin_emails)
    leaders = HrLite.normalize_email_list(HrLite.config.leadership_emails)
    # Pre-0.5.0 behaviour, still live on hosts that never set the money list:
    # an empty superadmin list meant "the same people as leadership".
    superadmins = leaders if superadmins.empty?

    assigned = Hash.new { |hash, key| hash[key] = [] }

    HrLite.config.employees_scope.call.find_each do |user|
      address = user.respond_to?(:email) ? user.email.to_s.downcase.strip : ""
      names = [ HrLite::Role::EMPLOYEE ]
      names << HrLite::Role::SUPER_ADMIN if address.present? && superadmins.include?(address)
      names << HrLite::Role::LEADERSHIP if address.present? && leaders.include?(address)
      names << HrLite::Role::HR if legacy_admin?(user)

      names.uniq.each do |name|
        role = roles[name] or next

        HrLite::RoleAssignment.create!(user_id: user.id, role: role)
        assigned[name] << HrLite.display_name(user)
      end
    end

    if assigned.empty?
      say "No users matched employees_scope — assign roles from the Roles screen."
    else
      assigned.each { |name, people| say "#{name}: #{people.sort.join(', ')}" }
    end
    say "Set `config.legacy_tier_checks = true` to keep the old email lists in " \
        "charge for now; it is honoured until 0.7.0."
  end

  # Assignments only — the roles themselves stay, because dropping them would
  # take every hand-made grant with them.
  def down
    HrLite::RoleAssignment.delete_all
  end

  private

  # admin_check is a host lambda over the host's own user model; a host whose
  # users do not answer it must not break the whole upgrade.
  def legacy_admin?(user)
    !!HrLite.config.admin_check.call(user)
  rescue StandardError => e
    say "admin_check raised for #{HrLite.display_name(user)} (#{e.class}) — treated as not HR."
    false
  end
end
