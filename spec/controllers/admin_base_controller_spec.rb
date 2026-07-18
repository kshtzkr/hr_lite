require "rails_helper"

RSpec.describe HrLite::Admin::BaseController, type: :controller do
  routes { HrLite::Engine.routes }

  controller do
    def index
      head :ok
    end
  end

  before do
    routes.draw { get "index", to: "hr_lite/admin/base#index" }
    HrLite.config.leadership_emails = [ "lead@x.test" ]
  end

  it "denies plain employees" do
    session[:user_id] = create(:user).id
    get :index
    expect(response).to redirect_to("/hr/")
  end

  it "admits admins" do
    session[:user_id] = create(:user, :admin).id
    get :index
    expect(response).to have_http_status(:ok)
  end

  it "admits leadership without admin flag (governing implies operating)" do
    session[:user_id] = create(:user, email: "lead@x.test").id
    get :index
    expect(response).to have_http_status(:ok)
  end

  it "responds 403 to non-HTML formats" do
    session[:user_id] = create(:user).id
    get :index, format: :json
    expect(response).to have_http_status(:forbidden)
  end
end
