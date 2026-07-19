require "rails_helper"

RSpec.describe HrLite::MentionParser do
  describe ".user_ids" do
    it "extracts ids from markers" do
      text = "Thanks @[Asha Rao](42) and @[Dev K](7)!"
      expect(described_class.user_ids(text)).to eq([ 42, 7 ])
    end

    it "dedupes and caps at the limit" do
      text = (1..15).map { |i| "@[U#{i}](#{i})" }.join(" ") + " @[U1](1)"
      expect(described_class.user_ids(text).length).to eq(described_class::LIMIT)
    end

    it "ignores malformed markers and nil" do
      expect(described_class.user_ids("@[NoId]() @[](3) @plain @[X](abc)")).to eq([])
      expect(described_class.user_ids(nil)).to eq([])
    end

    it "handles unicode names" do
      expect(described_class.user_ids("@[खुशबू](9)")).to eq([ 9 ])
    end
  end

  describe ".strip_markers" do
    it "replaces markers with @Name" do
      expect(described_class.strip_markers("Hi @[Asha](4)!")).to eq("Hi @Asha!")
    end
  end
end
