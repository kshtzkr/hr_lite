require "rails_helper"

RSpec.describe HrLite::OfficeLocation do
  describe "validations" do
    it "requires name and sane coordinates" do
      expect(build(:office_location, name: nil)).not_to be_valid
      expect(build(:office_location, lat: 91)).not_to be_valid
      expect(build(:office_location, lng: -181)).not_to be_valid
      expect(build(:office_location, radius_m: 0)).not_to be_valid
      expect(build(:office_location)).to be_valid
    end
  end

  describe ".covering?" do
    let!(:office) { create(:office_location, lat: 28.6315, lng: 77.2167, radius_m: 300) }

    it "is true within radius, false outside" do
      expect(described_class.covering?(28.6316, 77.2168)).to be(true)
      expect(described_class.covering?(28.6129, 77.2295)).to be(false)
    end

    it "ignores inactive offices" do
      office.update!(active: false)
      expect(described_class.covering?(28.6315, 77.2167)).to be(false)
    end
  end

  describe ".nearest" do
    it "returns the closest active office" do
      far = create(:office_location, name: "Far", lat: 19.0760, lng: 72.8777)
      near = create(:office_location, name: "Near", lat: 28.6315, lng: 77.2167)
      expect(described_class.nearest(28.63, 77.21)).to eq(near)
      expect(described_class.nearest(19.07, 72.87)).to eq(far)
    end
  end

  it "is audited as a policy change" do
    HrLite::Current.actor = create(:user)
    expect { create(:office_location) }.to change(HrLite::AuditLog, :count).by(1)
  ensure
    HrLite::Current.reset
  end
end
