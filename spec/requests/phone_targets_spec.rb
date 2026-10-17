require "rails_helper"

# Phone forms and tap targets: buttons, not 21px text links; labels, not
# placeholders; no employee picked unless somebody picked one.
RSpec.describe "Phone targets and forms", type: :request do
  let(:owner) { user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::SUPER_ADMIN, HrLite::Role::LEADERSHIP, name: "Asha") }

  def page = Nokogiri::HTML(response.body)

  it "gives tab-row links the 44px minimum" do
    css = HrLite::Engine.root.join("app/assets/stylesheets/hr_lite/hr_lite.css").read
    expect(css[/^\.hrl-tabrow \.hrl-nav__link \{[^}]*\}/]).to include("min-width: var(--hrl-target)")
  end

  it "draws work-time bar labels at a readable size whatever the range" do
    css = HrLite::Engine.root.join("app/assets/stylesheets/hr_lite/hr_lite.css").read
    expect(css).to include(".hrl-bars__label { font-size: 9px;", "calc(var(--hrl-bars-n, 0) * 1.75rem)")
  end

  it "makes list Edit links buttons" do
    create(:leave_type)
    sign_in owner
    get "/hr/admin/leave_types"
    expect(page.css("a").select { |a| a.text == "Edit" }.map { |a| a["class"] }).to all(eq("hrl-btn"))
  end

  it "puts the fix-a-punch links on the attendance page as buttons" do
    sign_in owner
    get "/hr/attendance"
    expect(page.at_css(%(a[href="/hr/regularization_requests/new"]))["class"]).to eq("hrl-btn")
  end

  it "labels the bulk holiday box" do
    sign_in owner
    get "/hr/admin/holidays"
    expect(page.at_css("label[for=bulk-lines]").text).to eq("One holiday a line: date, name")
  end

  it "lays the tax slab editor out as labelled 44px inputs" do
    sign_in owner
    get "/hr/admin/statutory_rate_cards/new"
    inputs = page.css(".hrl-slabs input")
    expect(inputs).to be_any
    expect(inputs.map { |i| i["class"] }.uniq).to eq([ "hrl-input" ])
    expect(inputs.first["aria-label"]).to eq("Band 1 from ₹")
  end

  it "makes the remaining list links buttons: rate-card Edit, report Open and CSV" do
    HrLite::StatutorySeeds.call
    sign_in owner
    get "/hr/admin/statutory_rate_cards"
    expect(page.css("a").select { |a| a.text == "Edit" }.map { |a| a["class"] }.uniq).to eq([ "hrl-btn" ])
    get "/hr/admin/reports"
    expect(page.css("a").select { |a| %w[Open CSV].include?(a.text) }.map { |a| a["class"] }.uniq).to eq([ "hrl-btn" ])
  end

  it "makes the loan list and a person's documents Open links buttons" do
    meera = user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera")
    HrLite::Loan.create!(user_id: meera.id, principal: BigDecimal("10000"), monthly_instalment: BigDecimal("1000"),
                         starts_on: Date.current.beginning_of_month)
    HrLite::Document.create!(user_id: meera.id, category: "offer_letter", title: "Offer letter",
                             file: { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "offer.pdf", content_type: "application/pdf" })
    sign_in owner
    [ "/hr/admin/loans", "/hr/admin/documents/for/#{meera.id}" ].each do |path|
      get path
      expect(page.css("a").select { |a| a.text == "Open" }.map { |a| a["class"] }).to eq([ "hrl-btn" ]), path
    end
  end

  it "starts every employee pick blank, required and filterable" do
    sign_in owner
    HrLite::Benefit.create!(name: "Group health", kind: "health", coverage: 500_000)
    ticket = HrLite::HrRequest.create!(user_id: owner.id, category: "other", subject: "Payslip query")
    [ "/hr/admin/payroll_line_items/new", "/hr/admin/loans/new", "/hr/admin/benefits", "/hr/admin/hr_requests/#{ticket.id}" ].each do |path|
      get path
      select = page.at_css("select[name='payroll_line_item[user_id]'], select[name='loan[user_id]'], select[name=user_id], select[name=assignee_id]")
      expect(select.at_css("option")["value"]).to eq(""), path
      expect(select["required"]).not_to be_nil
      expect(select["data-hrl-filter"]).to be_present
    end
  end
end
