require "rails_helper"

RSpec.describe "Benefits admin", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:benefit) { HrLite::Benefit.create!(name: "Group health", kind: "health", coverage: 500_000) }

  def enrol(user = employee, on: Date.current - 30, **extra)
    post "/hr/admin/benefits/#{benefit.id}/enrol", params: { user_id: user.id, enrolled_on: on, **extra }
  end

  describe "as HR" do
    before { sign_in hr }

    it "says so when no benefit has been added yet" do
      get "/hr/admin/benefits"
      expect(response.body).to include("No benefits yet")
    end

    it "adds a benefit, enrols somebody, and ends their cover" do
      post "/hr/admin/benefits", params: { benefit: { name: "Group health", kind: "health",
                                                      provider: "Acme", coverage: "500000" } }
      added = HrLite::Benefit.sole
      expect(added.coverage).to eq(500_000)

      post "/hr/admin/benefits/#{added.id}/enrol",
           params: { user_id: employee.id, enrolled_on: Date.current - 30, dependants: 2 }
      get "/hr/admin/benefits"
      expect(response.body).to include("Enrolled", "Meera", "5,00,000")

      sign_in employee
      get "/hr/benefits"
      expect(response.body).to include("Group health", "Acme", "5,00,000")

      sign_in hr
      post "/hr/admin/benefits/#{added.id}/unenrol", params: { user_id: employee.id, ended_on: Date.current - 1 }
      sign_in employee
      get "/hr/benefits"
      expect(response.body).to include("not enrolled in any benefit")
    end

    # ended_on is the LAST day of cover, so ending it today leaves today covered.
    it "ends cover today when no date is given" do
      enrol
      post "/hr/admin/benefits/#{benefit.id}/unenrol", params: { user_id: employee.id }
      expect(benefit.benefit_enrolments.sole.ended_on).to eq(Date.current)
    end

    it "refuses to enrol the same person twice" do
      enrol
      enrol
      expect(flash[:alert]).to include("already enrolled")
      expect(benefit.benefit_enrolments.count).to eq(1)
    end

    it "refuses cover that ends before it started" do
      enrol
      post "/hr/admin/benefits/#{benefit.id}/unenrol", params: { user_id: employee.id, ended_on: Date.current - 31 }
      expect(flash[:alert]).to include("on or after the enrolment date")
      expect(benefit.benefit_enrolments.sole.ended_on).to be_nil
    end

    it "refuses a policy that expires before it starts, and allows one that ends the day it starts" do
      params = { name: "Trip cover", kind: "accident", effective_from: "2026-10-10" }
      post "/hr/admin/benefits", params: { benefit: params.merge(expires_on: "2026-10-09") }
      expect(response).to have_http_status(:unprocessable_entity)

      expect { post "/hr/admin/benefits", params: { benefit: params.merge(expires_on: "2026-10-10") } }
        .to change(HrLite::Benefit, :count).by(1)
    end

    it "keeps cover that ends later on the list, and lets HR change its end" do
      enrol
      post "/hr/admin/benefits/#{benefit.id}/unenrol", params: { user_id: employee.id, ended_on: Date.current + 30 }
      get "/hr/admin/benefits"
      expect(response.body).to include("unenrol")

      post "/hr/admin/benefits/#{benefit.id}/unenrol", params: { user_id: employee.id, ended_on: Date.current + 5 }
      expect(HrLite::BenefitEnrolment.sole.ended_on).to eq(Date.current + 5)
    end

    it "offers only people still employed" do
      gone = create(:user, name: "Gone Person")
      create(:employee_profile, user: gone, date_of_joining: Date.new(2020, 1, 1), date_of_exit: Date.new(2021, 1, 1))
      benefit
      get "/hr/admin/benefits"
      expect(response.body).not_to include("Gone Person")
    end

    it "opens the add-benefit form" do
      get "/hr/admin/benefits/new"
      expect(response.body).to include("Premium the company pays")
    end
  end

  it "keeps benefits admin closed to an employee" do
    sign_in employee
    get "/hr/admin/benefits"
    expect(response).to redirect_to("/hr/")

    enrol
    expect(HrLite::BenefitEnrolment.count).to eq(0)
  end
end
