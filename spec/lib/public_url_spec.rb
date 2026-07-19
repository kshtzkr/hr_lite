require "rails_helper"

RSpec.describe "HrLite.public_url" do
  it "is nil (and public_url? false) when no base is configured" do
    expect(HrLite.public_url).to be_nil
    expect(HrLite.public_url("/kudos")).to be_nil
    expect(HrLite.public_url?("https://hr.acme.test/kudos")).to be(false)
  end

  it "builds absolute URLs from the configured base, trailing slash tolerant" do
    HrLite.config.public_url_base = "https://hr.acme.test/"
    expect(HrLite.public_url).to eq("https://hr.acme.test/")
    expect(HrLite.public_url("/kudos")).to eq("https://hr.acme.test/kudos")
  end

  it "allowlists only http(s) URLs on the configured host" do
    HrLite.config.public_url_base = "https://hr.acme.test"
    expect(HrLite.public_url?("https://hr.acme.test/leave_requests/4")).to be(true)
    expect(HrLite.public_url?("http://hr.acme.test/x")).to be(true)
    expect(HrLite.public_url?("https://evil.test/x")).to be(false)
    expect(HrLite.public_url?("javascript:alert(1)")).to be(false)
    expect(HrLite.public_url?("https://[bad")).to be(false)
    expect(HrLite.public_url?(nil)).to be(false)
  end

  it "keeps the 0.1.0 mail_link_base alias working" do
    HrLite.config.mail_link_base = "https://hr.acme.test"
    expect(HrLite.config.public_url_base).to eq("https://hr.acme.test")
    expect(HrLite.config.mail_link_base).to eq("https://hr.acme.test")
  end
end
