require "rails_helper"

RSpec.describe HrLite::HiringImport do
  let(:campaign) { HrLite::HiringCampaign.create!(title: "Drive", position: "Sales Intern") }
  let(:header) { [ "Sr. No.", "Student Name", "EMAIL ID.", "CONTACT NO.", "Campus", "Course Pursuing ", "12%age/CGPA", "Link for CV" ] }

  def build(rows, picks: {}) = described_class.new(campaign, [ header, *rows ], picks: picks)

  it "maps a university's headers, keeps unknown columns and imports" do
    import = build([ [ 1.0, "Asha Rao", " Asha@Example.com ", 9876543210.0, "Noida", "BBA", "82%", "https://cv.example/a" ] ])

    expect(import.columns.map(&:field)).to eq([ nil, "name", "email", "phone", "campus", "course", nil, "cv_url" ])
    expect(import.columns.map(&:extra_key).compact).to eq(%w[sr_no sheet_12_age_cgpa])
    expect(import.import!).to be(true)

    asha = campaign.candidates.sole
    expect([ asha.email, asha.phone, asha.course, asha.extra ]).to eq([ "asha@example.com", "9876543210", "BBA", { "sr_no" => "1", "sheet_12_age_cgpa" => "82%" } ])
    expect(asha.timeline.pluck(:action)).to eq([ "hiring.imported" ])
  end

  it "reads the same data under renamed, reordered headers" do
    import = described_class.new(campaign, [ [ "Mobile", "e-mail", "Full Name", "College" ], [ "99", "b@x.in", "Bina", "Pune" ] ])
    import.import!
    expect(campaign.candidates.sole.slice(:name, :email, :phone, :campus).values).to eq([ "Bina", "b@x.in", "99", "Pune" ])
  end

  it "holds two columns claiming one field until HR picks, keeping the loser as extra" do
    rows = [ [ "Name", "Email", "CONTACT NO.", "Mobile" ], [ "Asha", "a@x.in", "111", "222" ] ]
    import = described_class.new(campaign, rows)
    expect(import.conflicts.keys).to eq([ "phone" ])
    expect(import.import!).to be(false)

    described_class.new(campaign, rows, picks: { "phone" => "3" }).import!
    expect(campaign.candidates.sole.slice(:phone, :extra).values).to eq([ "222", { "contact_no" => "111" } ])
  end

  it "never lets an extra column take a reserved placeholder's name" do
    import = described_class.new(campaign, [ [ "Name", "Email", "Stipend", "" ], [ "Asha", "a@x.in", "5000", "x" ] ])
    expect(import.columns.map(&:extra_key).compact).to eq(%w[sheet_stipend column_4])
  end

  it "explains every skipped row, ignores empty ones, and updates on a repeat upload" do
    campaign.candidates.create!(name: "Old", email: "old@x.in", stage: "invited")
    import = build([
      [ 1, "Asha", "a@x.in" ], [ 2, "", "b@x.in" ], [ 3, "Chen", "" ], [ 4, "Dev", "not-an-email" ],
      [ 5, "Asha again", "A@x.in" ], [ nil, nil, nil ], [ 6, "Old Name", "old@x.in", nil, nil, Date.new(2003, 5, 1) ]
    ])

    expect(import.rows.map { |r| [ r.number, r.outcome, r.reason ] }).to eq([
      [ 2, "create", nil ], [ 3, "skip", "no name" ], [ 4, "skip", "no email address" ],
      [ 5, "skip", "email address looks wrong" ], [ 6, "skip", "same email as row 2" ], [ 8, "update", nil ]
    ])
    expect(import.counts).to eq("create" => 1, "update" => 1, "skip" => 4)
    import.import!
    old = campaign.candidates.find_by!(email: "old@x.in")
    expect([ old.name, old.stage, old.course ]).to eq([ "Old Name", "invited", "01/05/2003" ])
    expect(old.timeline.pluck(:action)).to eq([ "hiring.reimported" ])
  end

  it "turns cells into text without evaluating them" do
    expect([ nil, 2.5, Time.utc(2003, 5, 1), "=1+1 ", 7 ].map { |v| described_class.text(v) }).to eq([ "", "2.5", "01/05/2003", "=1+1", "7" ])
  end
end
