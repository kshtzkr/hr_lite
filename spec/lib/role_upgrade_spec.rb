require "rails_helper"
require Rails.root.join("../../db/migrate/20260817183629_seed_hr_lite_roles_from_email_tiers.rb")

# The migration that decides whether a live install loses access on upgrade.
# It reads the host's OWN configuration and lands everybody where they already
# were; an upgrade that silently grants the money tier to the wrong person, or
# silently locks the owner out, is the failure worth pinning hardest.
RSpec.describe SeedHrLiteRolesFromEmailTiers, no_legacy_bridge: true do
  subject(:migration) { described_class.new.tap { |m| m.verbose = false } }

  let!(:money) { create(:user, email: "owner@acme.test", name: "Owner") }
  let!(:leader) { create(:user, email: "boss@acme.test", name: "Boss") }
  let!(:ops) { create(:user, :admin, email: "hr@acme.test", name: "Ops") }
  let!(:plain) { create(:user, email: "dev@acme.test", name: "Dev") }

  before do
    HrLite.config.superadmin_emails = [ "owner@acme.test" ]
    HrLite.config.leadership_emails = [ "boss@acme.test", "owner@acme.test" ]
    HrLite::RoleAssignment.delete_all
    HrLite::Role.delete_all
  end

  def roles_for(user)
    HrLite::RoleAssignment.where(user_id: user.id).includes(:role).map { |a| a.role.name }.sort
  end

  it "lands everybody exactly where the email lists had them" do
    migration.up

    expect(roles_for(money)).to eq([ HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP,
                                     HrLite::Role::SUPER_ADMIN ].sort)
    expect(roles_for(leader)).to eq([ HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP ].sort)
    expect(roles_for(ops)).to eq([ HrLite::Role::EMPLOYEE, HrLite::Role::HR ].sort)
    expect(roles_for(plain)).to eq([ HrLite::Role::EMPLOYEE ])
  end

  it "leaves everyone with at least the access they had" do
    before_upgrade = { money => true, leader => false, ops => false, plain => false }
    migration.up
    HrLite::Current.access_cache = nil

    expect(HrLite.superadmin?(money.reload)).to be(true)
    expect(HrLite.leadership?(leader.reload)).to be(true)
    expect(HrLite.admin?(ops.reload)).to be(true)
    expect(HrLite.leadership?(plain.reload)).to be(false)

    # And nobody GAINED the money tier who did not have it.
    before_upgrade.each do |user, had_money|
      expect(HrLite.superadmin?(user.reload)).to eq(had_money)
    end
  end

  # Pre-0.5.0 behaviour, still live on hosts that never set the money list.
  it "treats an unset money list as 'the same people as leadership'" do
    HrLite.config.superadmin_emails = []
    migration.up

    expect(roles_for(leader)).to include(HrLite::Role::SUPER_ADMIN)
  end

  it "does not re-derive anything on a host that already assigned roles" do
    HrLite::RoleSeeds.call
    HrLite::RoleAssignment.create!(user_id: plain.id,
                                   role: HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN))

    migration.up

    # The hand-made grant stands, and the email lists are not consulted:
    # `money` is on both of them and still gets neither role.
    expect(roles_for(plain)).to include(HrLite::Role::SUPER_ADMIN)
    expect(roles_for(money)).not_to include(HrLite::Role::SUPER_ADMIN,
                                            HrLite::Role::LEADERSHIP)
  end

  it "survives an admin_check that raises on somebody's row" do
    HrLite.config.admin_check = ->(user) { raise "no such column" if user.id == ops.id; false }

    expect { migration.up }.not_to raise_error
    expect(roles_for(ops)).to eq([ HrLite::Role::EMPLOYEE ])
    expect(roles_for(leader)).to include(HrLite::Role::LEADERSHIP)
  end

  it "seeds roles without assigning anybody when the scope is empty" do
    HrLite.config.employees_scope = -> { HrLite.user_klass.none }
    migration.up

    expect(HrLite::Role.count).to eq(HrLite::RoleSeeds.definitions.size)
    expect(HrLite::RoleAssignment.count).to eq(0)
  end

  it "rolls back the assignments but keeps the roles and their tuning" do
    migration.up
    HrLite::Role.find_by!(name: HrLite::Role::HR).replace_grants!("audit.view" => "all")

    migration.down

    expect(HrLite::RoleAssignment.count).to eq(0)
    expect(HrLite::Role.find_by!(name: HrLite::Role::HR).grant_map).to eq("audit.view" => "all")
  end
end

RSpec.describe HrLite::RoleSeeds, no_legacy_bridge: true do
  it "never overwrites a role an install has tuned" do
    described_class.call
    hr = HrLite::Role.find_by!(name: HrLite::Role::HR)
    hr.replace_grants!("leave.view" => "self")

    expect(described_class.call).to be_empty
    expect(hr.reload.grant_map).to eq("leave.view" => "self")
  end

  it "grants the money role every declared permission" do
    described_class.call
    owner = HrLite::Role.find_by!(name: HrLite::Role::SUPER_ADMIN)

    expect(owner.grant_map.keys).to match_array(HrLite::Permissions::KEYS)
    expect(owner.grant_map.values.uniq).to eq([ "all" ])
  end

  it "gives a manager their team and never the whole company" do
    described_class.call
    manager = HrLite::Role.find_by!(name: HrLite::Role::MANAGER)

    expect(manager.grant_map["leave.approve"]).to eq("team")
    expect(manager.grant_map.values).not_to include("all")
  end

  it "keeps pay away from Leadership and people away from Finance" do
    described_class.call
    leadership = HrLite::Role.find_by!(name: HrLite::Role::LEADERSHIP).grant_map
    finance = HrLite::Role.find_by!(name: HrLite::Role::FINANCE).grant_map

    expect(leadership).not_to include("salary.view", "payroll.manage")
    expect(finance).not_to include("profile.manage", "settings.manage")
  end

  it "declares only permissions that exist" do
    described_class.definitions.each_value do |definition|
      definition[:grants].each_key { |key| expect(HrLite::Permissions).to be_valid(key) }
    end
  end
end
