require "rails_helper"

RSpec.describe "Salary slips before and after config.slip_release_day", type: :request do
  let(:ist) { Time.find_zone("Asia/Kolkata") }
  let(:user) { create(:user) }
  let(:october) { published_slip(Date.new(2027, 10, 1)) }
  let(:september) { published_slip(Date.new(2027, 9, 1)) }

  before { HrLite.config.slip_release_day = 10 }

  def published_slip(month)
    travel_to(ist.local(2027, 11, 6)) do
      slip = create(:salary_slip, user: user, payroll_run: create(:payroll_run, period_month: month),
                                  gross_earnings: 60000, total_deductions: 10000, net_pay: 50000)
      slip.payroll_run.update_columns(status: "published") # rubocop:disable Rails/SkipsModelValidations
      slip
    end
  end

  it "hides October's slip until 10 November in IST" do
    october && september
    sign_in user

    travel_to(ist.local(2027, 11, 9, 23, 30)) do
      get "/hr/salary_slips"
      expect(response.body).to include("September 2027")
      expect(response.body).not_to include("October 2027")
      get "/hr/salary_slips/#{october.id}"
      expect(response).to have_http_status(:not_found)
      get "/hr/salary_slips/#{october.id}.pdf"
      expect(response).to have_http_status(:not_found)
    end

    travel_to(ist.local(2027, 11, 10, 0, 30)) do
      get "/hr/salary_slips"
      expect(response.body).to include("October 2027")
      get "/hr/salary_slips/#{october.id}"
      expect(response).to have_http_status(:ok)
    end
  end
end
