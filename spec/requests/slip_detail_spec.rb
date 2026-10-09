require "rails_helper"

RSpec.describe "Slip detail summary", type: :request do
  let(:user) { create(:user, email: "lead@x.test") }
  let(:slip) do
    create(:salary_slip, user: user, gross_earnings: 60_000, total_deductions: 10_000, net_pay: 50_000,
                         payable_days: 28, lop_days: 2).tap do |s|
      s.payroll_run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def kpi_values = Nokogiri::HTML(response.body).css(".hrl-kpi__value").map { |n| n.text.strip }

  before { sign_in user }

  it "leads the employee slip with net pay, gross, deductions and days" do
    get "/hr/salary_slips/#{slip.id}"
    expect(kpi_values).to eq([ HrLite::Money.format(slip.net_pay), "₹60,000.00", "₹10,000.00", "28 / 2" ])
  end

  it "shows the same tiles on the admin slip view, which renders the same partial" do
    HrLite.config.leadership_emails = [ "lead@x.test" ]
    get "/hr/admin/salary_slips/#{slip.id}"
    expect(kpi_values.first).to eq(HrLite::Money.format(slip.net_pay))
    expect(response.body).to include("Tax working")
  end
end
