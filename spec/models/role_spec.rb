require "rails_helper"

RSpec.describe HrLite::Role, no_legacy_bridge: true do
  describe "built-in roles" do
    subject(:role) { described_class.create!(name: "Ops", system: true) }

    # The seed, the upgrade migration and the specs all identify these by
    # name. The permissions inside them are what an install is meant to
    # re-cut; what they are called is not.
    it "refuses a rename" do
      role.name = "Operations"

      expect(role.save).to be(false)
      expect(role.errors[:name]).to include("cannot be changed on a built-in role")
      expect(role.reload.name).to eq("Ops")
    end

    it "allows everything else to change" do
      expect(role.update(description: "Runs the day to day")).to be(true)
    end

    it "refuses to be deleted" do
      expect(role.destroy).to be(false)
      expect(described_class.exists?(role.id)).to be(true)
    end
  end

  describe "an install's own role" do
    subject(:role) { described_class.create!(name: "Auditor") }

    it "renames and deletes freely" do
      expect(role.update(name: "Reviewer")).to be(true)
      expect(role.destroy).to be_truthy
    end

    it "takes its grants with it" do
      role.replace_grants!("audit.view" => "all")
      expect { role.destroy }.to change(HrLite::RoleGrant, :count).by(-1)
    end
  end

  describe "#replace_grants!" do
    subject(:role) { described_class.create!(name: "Auditor") }

    it "drops what is absent and ignores 'none'" do
      role.replace_grants!("audit.view" => "all", "payroll.view" => "all")
      role.replace_grants!("audit.view" => "team", "payroll.view" => "none")

      expect(role.grant_map).to eq("audit.view" => "team")
    end

    it "refuses a permission nobody declared" do
      expect { role.replace_grants!("audit.viewe" => "all") }
        .to raise_error(ArgumentError, /Unknown HrLite permission/)
      expect(role.reload.grant_map).to be_empty
    end

    it "refuses a scope that is not one of the three" do
      expect { role.replace_grants!("audit.view" => "everything") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "refuses two roles with the same name, whatever the casing" do
    described_class.create!(name: "Auditor")
    expect(described_class.new(name: "auditor")).not_to be_valid
  end
end
