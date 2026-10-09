require "rails_helper"

RSpec.describe "PIP admin", type: :request, no_legacy_bridge: true do
  let(:asha) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Asha") }
  let(:dev) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Dev") }
  let(:bells) { [] }

  before { HrLite.config.notify = ->(**kw) { bells << kw } }

  it "lets Super Admin start a PIP, then close it for good, telling the employee each time" do
    sign_in asha
    get "/hr/admin/performance_plans/new", params: { user_id: dev.id }
    expect(response.body).to include("Start a performance improvement plan")

    post "/hr/admin/performance_plans", params: { performance_plan: { user_id: dev.id, start_date: Date.current,
                                                                      end_date: Date.current + 30, goals: "Close 10 files" } }
    plan = HrLite::PerformancePlan.sole
    expect(plan.created_by_id).to eq(asha.id)

    patch "/hr/admin/performance_plans/#{plan.id}", params: { performance_plan: { status: "failed", outcome_note: "Missed" } }
    expect(plan.reload.closed_at).to be_present
    get "/hr/admin/performance_plans"
    expect(response.body).to include("Dev", "Failed")

    get "/hr/admin/performance_plans/#{plan.id}/edit"
    expect(flash[:alert]).to eq("A closed PIP cannot be changed.")
    expect(bells.select { |b| b[:kind].start_with?("pip.") }.map { |b| [ b[:user], b[:kind] ] }).to eq([ [ dev, "pip.started" ], [ dev, "pip.closed" ] ])
  end

  it "refuses a PIP that ends before it starts" do
    sign_in asha
    post "/hr/admin/performance_plans", params: { performance_plan: { user_id: dev.id, start_date: Date.current,
                                                                      end_date: Date.current - 1, goals: "x" } }
    expect(response).to have_http_status(:unprocessable_entity)
    patch "/hr/admin/performance_plans/#{HrLite::PerformancePlan.create!(user: dev, start_date: Date.current, end_date: Date.current + 9, goals: "x").id}",
          params: { performance_plan: { goals: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "keeps HR, Leadership and managers out" do
    [ HrLite::Role::HR, HrLite::Role::LEADERSHIP, HrLite::Role::MANAGER ].each do |role|
      sign_in user_with_roles(role)
      get "/hr/admin/performance_plans"
      expect(response).to redirect_to("/hr/")
    end
  end
end
