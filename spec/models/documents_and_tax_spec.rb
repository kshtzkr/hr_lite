require "rails_helper"

RSpec.describe HrLite::Document, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:money) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let!(:owner) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:stranger) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }

  def document(**attrs)
    described_class.create!({ user_id: owner.id, category: "certificate",
                              title: "Degree" }.merge(attrs))
  end

  describe "who may open the file" do
    it "is always the person it belongs to" do
      expect(document.readable_by?(owner)).to be(true)
    end

    it "is never a colleague" do
      expect(document.readable_by?(stranger)).to be(false)
      expect(document.readable_by?(nil)).to be(false)
    end

    it "is HR for an ordinary document" do
      expect(document(visibility: "hr").readable_by?(hr)).to be(true)
    end

    # An Aadhaar or a bank mandate is not HR's to browse by default.
    it "defaults an identity document to the money tier alone" do
      aadhaar = document(category: "aadhaar", title: "Aadhaar")

      expect(aadhaar.visibility).to eq("money")
      expect(aadhaar.readable_by?(hr)).to be(false)
      expect(aadhaar.readable_by?(money)).to be(true)
      expect(aadhaar.readable_by?(owner)).to be(true)
    end

    it "defaults an ordinary document to HR" do
      expect(document(category: "certificate").visibility).to eq("hr")
    end

    it "keeps a `self` document to its owner, HR included" do
      private_doc = document(visibility: "self")

      expect(private_doc.readable_by?(owner)).to be(true)
      expect(private_doc.readable_by?(hr)).to be(false)
      expect(private_doc.readable_by?(money)).to be(false)
    end

    it "respects an explicit visibility over the category default" do
      expect(document(category: "aadhaar", visibility: "hr").visibility).to eq("hr")
    end
  end

  describe "the file itself" do
    def attach(doc, content_type:, bytes: 1.kilobyte)
      doc.file.attach(io: StringIO.new("x" * bytes), filename: "f",
                      content_type: content_type)
      doc
    end

    it "accepts a PDF" do
      expect(attach(described_class.new(user_id: owner.id, category: "offer_letter",
                                        title: "Offer"), content_type: "application/pdf")).to be_valid
    end

    # SVG and HTML both carry script and both render in a browser.
    it "refuses an SVG however it is labelled" do
      doc = attach(described_class.new(user_id: owner.id, category: "certificate", title: "X"),
                   content_type: "image/svg+xml")

      expect(doc).not_to be_valid
      expect(doc.errors[:file].join).to include("PDF or an image")
    end

    it "refuses a file over the size cap" do
      doc = attach(described_class.new(user_id: owner.id, category: "certificate", title: "X"),
                   content_type: "application/pdf", bytes: 11.megabytes)

      expect(doc).not_to be_valid
      expect(doc.errors[:file].join).to include("under 10 MB")
    end
  end

  describe "verification" do
    it "records who checked it" do
      doc = document
      doc.verify!(actor: hr)

      expect(doc.reload).to be_verified
      expect(doc.verified_by_id).to eq(hr.id)
    end

    it "refuses a rejection with no reason" do
      expect { document.reject!(actor: hr, note: " ") }.to raise_error(ArgumentError)
    end

    it "records a rejection with its reason" do
      doc = document
      doc.reject!(actor: hr, note: "Scan is unreadable")

      expect(doc.reload.verification).to eq("rejected")
      expect(doc.verification_note).to eq("Scan is unreadable")
      expect(doc.verified_by_id).to eq(hr.id)
    end
  end

  describe "expiry" do
    it "knows what has lapsed" do
      expect(document(expires_on: Date.current - 1)).to be_expired
      expect(document(expires_on: Date.current + 1)).not_to be_expired
      expect(document(expires_on: nil)).not_to be_expired
    end

    it "finds what is about to lapse" do
      soon = document(title: "Passport", expires_on: Date.current + 10)
      document(title: "Later", expires_on: Date.current + 400)

      expect(described_class.expiring_before(Date.current + 30)).to contain_exactly(soon)
    end
  end
end

RSpec.describe HrLite::TaxDeclaration, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let(:fy) { Date.new(2027, 4, 1) }

  def declaration(status: "draft", **items)
    d = described_class.create!(user_id: employee.id, financial_year: fy,
                                regime: "old", status: status)
    items.each { |section, amount| d.tax_declaration_items.create!(section: section.to_s, declared_amount: amount) }
    d
  end

  it "labels each section in words rather than a code" do
    d = declaration("80c": 1, "80d": 1, "80ccd_1b": 1, "24b": 1, hra: 1, other: 1)

    expect(d.tax_declaration_items.map(&:section_label))
      .to include("80C \u2014 investments", "80D \u2014 health insurance", "80CCD(1B) \u2014 NPS",
                  "24(b) \u2014 home loan interest", "HRA exemption", "Other")
  end

  it "refuses a negative amount" do
    d = declaration
    expect(d.tax_declaration_items.new(section: "80c", declared_amount: -1)).not_to be_valid
  end

  it "adds its sections up" do
    d = declaration("80c": 150_000, "80d": 25_000)
    expect(d.declared_total).to eq(175_000)
  end

  it "refuses a second declaration for the same year" do
    declaration
    expect(described_class.new(user_id: employee.id, financial_year: fy)).not_to be_valid
  end

  it "refuses a year that does not open in April" do
    expect(described_class.new(user_id: employee.id, financial_year: Date.new(2027, 7, 1)))
      .not_to be_valid
  end

  describe "what payroll may deduct against" do
    # Asking somebody to overpay tax all year because paperwork is slow is
    # its own kind of wrong, so the declared figure stands until HR looks.
    it "is what was declared, until it has been verified" do
      d = declaration(status: "submitted", "80c": 150_000)
      expect(d.allowable_total).to eq(150_000)
    end

    # And once HR HAS looked, only what the proof supported counts.
    it "is what the proof supported, once verified" do
      d = declaration(status: "submitted", "80c": 150_000)
      d.tax_declaration_items.first.update!(verified_amount: 90_000)
      d.verify!(actor: finance)

      expect(d.reload.allowable_total).to eq(90_000)
    end

    it "is zero when verification supported nothing" do
      d = declaration(status: "submitted", "80c": 150_000)
      d.verify!(actor: finance)

      expect(d.reload.allowable_total).to eq(0)
    end
  end

  describe "the lifecycle" do
    it "submits, notifies whoever manages tax, then verifies" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }
      d = declaration("80c": 100_000)

      d.submit!(actor: employee)
      expect(d.reload).to be_submitted
      expect(bells.map { |b| b[:user] }).to include(finance)

      d.verify!(actor: finance)
      expect(d.reload).to be_verified
    end

    it "lets a rejected declaration be corrected and resubmitted" do
      d = declaration(status: "submitted")
      d.reject!(actor: finance, note: "80C proof missing")

      expect(d.reload).to be_rejected
      expect { d.submit!(actor: employee) }.not_to raise_error
    end

    it "refuses to verify something nobody submitted" do
      expect { declaration.verify!(actor: finance) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses a rejection with no reason" do
      expect { declaration(status: "submitted").reject!(actor: finance, note: "") }
        .to raise_error(ArgumentError)
    end
  end
end

RSpec.describe HrLite::DocumentExpiryJob, no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  def document(expires_on:)
    HrLite::Document.create!(user_id: employee.id, category: "passport",
                             title: "Passport", expires_on: expires_on)
  end

  it "warns at thirty days and again at seven" do
    document(expires_on: Date.current + 30)
    document(expires_on: Date.current + 7)
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now

    expect(bells.size).to eq(2)
    expect(bells.map { |b| b[:title] }).to include(/30 days/, /7 days/)
  end

  # Not every day for a month — a warning that arrives daily is a warning
  # nobody reads by the third one.
  it "says nothing on the days in between" do
    document(expires_on: Date.current + 21)
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now
    expect(bells).to be_empty
  end

  it "says nothing about a document with no expiry" do
    document(expires_on: nil)
    bells = []
    HrLite.config.notify = ->(**kw) { bells << kw }

    described_class.perform_now
    expect(bells).to be_empty
  end
end

# The declaration is what the whole year's TDS is projected from, so how
# payroll picks the figure it uses is the part worth pinning.
RSpec.describe "TDS reads the declaration", no_legacy_bridge: true do
  let(:leader) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }
  let(:month) { Date.new(2027, 6, 1) } # FY 2027-28

  around { |example| travel_to(Date.new(2027, 7, 5)) { example.run } }

  def slip_for(profile)
    run = HrLite::PayrollRun.find_or_create_by!(period_month: month)
    run.compute!(actor: leader)
    run.salary_slips.find_by!(user_id: profile.user_id)
  end

  def big_earner(**profile_attrs)
    profile = create(:employee_profile, tax_regime: "old", **profile_attrs)
    create(:salary_structure, user: profile.user, basic: 120_000, hra: 60_000,
                              special_allowance: 40_000)
    profile
  end

  def declare!(profile, amount, status:)
    d = HrLite::TaxDeclaration.create!(user_id: profile.user_id, regime: "old",
                                       financial_year: Date.new(2027, 4, 1), status: status)
    d.tax_declaration_items.create!(section: "80c", declared_amount: amount)
    d
  end

  it "falls back to the profile figure when nobody filed a declaration" do
    profile = big_earner(declared_annual_deductions: 150_000)
    details = slip_for(profile).tax_details_hash

    expect(BigDecimal(details["declared_deductions"])).to eq(150_000)
  end

  # A draft is not a claim. Until it is submitted the old figure stands.
  it "ignores a declaration still in draft" do
    profile = big_earner(declared_annual_deductions: 150_000)
    declare!(profile, 400_000, status: "draft")

    expect(BigDecimal(slip_for(profile).tax_details_hash["declared_deductions"])).to eq(150_000)
  end

  it "uses a submitted declaration over the profile figure" do
    profile = big_earner(declared_annual_deductions: 150_000)
    declare!(profile, 200_000, status: "submitted")

    expect(BigDecimal(slip_for(profile).tax_details_hash["declared_deductions"])).to eq(200_000)
  end

  it "uses only what the proof supported once it is verified" do
    profile = big_earner(declared_annual_deductions: 150_000)
    declaration = declare!(profile, 200_000, status: "submitted")
    declaration.tax_declaration_items.first.update!(verified_amount: 50_000)
    declaration.verify!(actor: leader)

    expect(BigDecimal(slip_for(profile).tax_details_hash["declared_deductions"])).to eq(50_000)
  end

  # The regime is a per-YEAR choice, and the declaration is where the
  # employee records it.
  it "follows the regime the declaration names" do
    profile = big_earner(declared_annual_deductions: 0)
    HrLite::TaxDeclaration.create!(user_id: profile.user_id, regime: "new",
                                   financial_year: Date.new(2027, 4, 1), status: "submitted")

    expect(slip_for(profile).tax_details_hash["regime"]).to eq("new")
  end
end
