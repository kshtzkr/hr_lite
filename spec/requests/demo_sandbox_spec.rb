require "rails_helper"

# The bin/demo persona picker that ships in the dummy app. Inert unless
# HR_LITE_DEMO=1 (the sandbox boot flag).
RSpec.describe "Demo sandbox", type: :request do
  context "outside demo mode" do
    it "404s the picker and keeps the bare 401 auth contract" do
      get "/"
      expect(response).to have_http_status(:not_found)

      get "/hr/kudos"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "in demo mode" do
    around do |example|
      ENV["HR_LITE_DEMO"] = "1"
      example.run
    ensure
      ENV.delete("HR_LITE_DEMO")
    end

    it "lists personas, signs in on click and redirects the signed-out to the picker" do
      user = create(:user, name: "Meera (Employee)")

      get "/hr/kudos"
      expect(response).to redirect_to("/")

      get "/"
      expect(response.body).to include("Meera (Employee)")

      post "/demo/sign_in/#{user.id}"
      expect(response).to redirect_to("/hr")
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end
  end
end
