require "rails_helper"

RSpec.describe "Career models" do
  let(:leader) { create(:user, email: "lead@x.test") }
  let(:profile) { create(:employee_profile, designation: "Executive") }

  before { HrLite.config.leadership_emails = [ "lead@x.test" ] }

  describe HrLite::Appraisal do
    def build_appraisal(**attrs)
      build(:appraisal, { user: profile.user, reviewer: leader }.merge(attrs))
    end

    it "validates ratings, periods and outcome requirements" do
      expect(build_appraisal(rating: 6)).not_to be_valid
      expect(build_appraisal(rating: nil)).to be_valid
      expect(build_appraisal(period_end: Date.new(2026, 1, 1))).not_to be_valid
      expect(build_appraisal(outcome: "increment", effective_date: nil)).not_to be_valid
      expect(build_appraisal(outcome: "promotion", effective_date: Date.current,
                             new_designation: nil)).not_to be_valid
      expect(build_appraisal(outcome: "promotion", effective_date: Date.current,
                             new_designation: "Manager")).to be_valid
    end

    describe "#share!" do
      it "shares once, notifies the employee, locks edits and refuses destroy" do
        bells = []
        HrLite.config.notify = ->(**kw) { bells << kw }
        appraisal = create(:appraisal, user: profile.user, reviewer: leader, rating: 4)

        expect(appraisal.share!(actor: leader)).to be(true)
        expect(appraisal.reload).to be_shared
        expect(bells.map { |b| b[:kind] }).to include("appraisal.shared")

        expect { appraisal.share!(actor: leader) }.to raise_error(ActiveRecord::RecordInvalid)
        expect { appraisal.update!(rating: 1) }.to raise_error(ActiveRecord::RecordInvalid)
        expect(appraisal.destroy).to be(false)
      end

      it "records a designation change on promotion outcomes" do
        appraisal = create(:appraisal, user: profile.user, reviewer: leader,
                           outcome: "promotion", new_designation: "Senior Executive",
                           effective_date: Date.new(2027, 7, 1))

        expect { appraisal.share!(actor: leader) }.to change(HrLite::DesignationChange, :count).by(1)

        change = HrLite::DesignationChange.last
        expect(change.from_designation).to eq("Executive")
        expect(change.to_designation).to eq("Senior Executive")
        expect(change.appraisal_id).to eq(appraisal.id)
        expect(profile.reload.designation).to eq("Senior Executive")
      end
    end

    it "destroys drafts freely" do
      appraisal = create(:appraisal, user: profile.user, reviewer: leader)
      expect { appraisal.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe HrLite::DesignationChange do
    it "captures from_designation, syncs the profile and calls the host hook" do
      synced = []
      HrLite.config.on_designation_change = ->(user, designation) { synced << [ user.id, designation ] }

      change = HrLite::DesignationChange.create!(
        user_id: profile.user_id, to_designation: "Manager",
        effective_date: Date.current, created_by_id: leader.id
      )

      expect(change.from_designation).to eq("Executive")
      expect(profile.reload.designation).to eq("Manager")
      expect(synced).to eq([ [ profile.user_id, "Manager" ] ])
    end

    it "survives a failing host hook" do
      HrLite.config.on_designation_change = ->(*) { raise "host broke" }
      expect {
        HrLite::DesignationChange.create!(user_id: profile.user_id, to_designation: "Lead",
                                          effective_date: Date.current)
      }.not_to raise_error
    end

    it "notifies the employee and leadership" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      HrLite::DesignationChange.create!(user_id: profile.user_id, to_designation: "Lead",
                                        effective_date: Date.current)
      kinds = bells.map { |b| b[:kind] }
      expect(kinds).to include("promotion.recorded")
    end

    it "is append-only" do
      change = HrLite::DesignationChange.create!(user_id: profile.user_id, to_designation: "Lead",
                                                 effective_date: Date.current)
      expect { change.update!(to_designation: "Tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "works without an employee profile (designation lives only on the timeline)" do
      loner = create(:user)
      expect {
        HrLite::DesignationChange.create!(user_id: loner.id, to_designation: "Contractor",
                                          effective_date: Date.current)
      }.to change(HrLite::DesignationChange, :count).by(1)
    end
  end
end
