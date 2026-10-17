require "rails_helper"

# Figures on a phone: no number split mid-digit, and every total counts what it says.
RSpec.describe "Money that reads right", type: :request do
  let(:meera) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }

  it "sizes payroll run totals as money tiles and calls employer PF/ESI what it is" do
    run = create(:payroll_run)
    sign_in owner
    get "/hr/admin/payroll_runs/#{run.id}"
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".hrl-kpis")["class"]).to include("hrl-kpis--money")
    expect(page.css(".hrl-kpi__label").map(&:text)).to include("Employer contributions")
  end

  it "stacks the slip's earnings table on a phone, one labelled row per figure" do
    slip = create(:salary_slip, user: meera, gross_earnings: 60_000, net_pay: 50_000, total_deductions: 10_000,
                                earnings: [ { "label" => "Basic", "amount" => "30000", "full_amount" => "30000" } ].to_json)
    slip.payroll_run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    sign_in meera
    get "/hr/salary_slips/#{slip.id}"
    table = Nokogiri::HTML(response.body).at_css(".hrl-card table.hrl-table--stack")
    expect(table.css("tbody tr:first-child td").map { |td| td["data-label"] }).to eq(%w[Component Full Earned])
    expect(slip.pdf_cache_key).to start_with("hr_lite_slip_v3/") # the PDF's words changed too
  end

  it "keeps tax-working amounts on one line" do
    css = HrLite::Engine.root.join("app/assets/stylesheets/hr_lite/hr_lite.css").read
    expect(css[/^\.hrl-tax-working__table td \{[^}]*\}/]).not_to include("anywhere")
    expect(css).to include(".hrl-tax-working__table td.hrl-num { white-space: nowrap; }")
  end

  it "counts only active loans as outstanding" do
    %w[active cancelled closed].each do |status|
      HrLite::Loan.create!(user_id: meera.id, principal: BigDecimal("10000"), monthly_instalment: BigDecimal("1000"),
                           starts_on: Date.current.beginning_of_month, status: status)
    end
    sign_in meera
    get "/hr/loans"
    expect(response.body).to include("Outstanding across everything: <strong>₹10,000.00</strong>")
  end

  it "shows pending days on the balance chip" do
    type = create(:leave_type, name: "Casual", code: "CL", annual_quota: 12)
    create(:leave_request, user: meera, leave_type: type, start_date: Date.current.next_occurring(:wednesday), end_date: Date.current.next_occurring(:wednesday))
    sign_in meera
    get "/hr/leave_requests"
    expect(response.body).to match(/Casual · [\d.]+ of [\d.]+ left · 1 pending/)
  end
end
