require "rails_helper"

RSpec.describe HrLite::Seeds do
  it "runs cleanly with no phase seeders defined yet" do
    expect(described_class.run!).to eq([])
  end
end
