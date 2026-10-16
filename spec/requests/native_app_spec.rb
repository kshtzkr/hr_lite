require "rails_helper"

# The host's iOS/Android staff apps drive pages with Hotwire Native, which needs
# Turbo on the page. Browsers keep the engine's plain, Turbo-free pages.
RSpec.describe "Native app shell", type: :request do
  let(:employee) { create(:user) }

  before { sign_in employee }

  it "loads Turbo, with every visit a full page load, inside the apps" do
    get "/hr/", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS;" }

    expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
    tag = response.body[%r{<script[^>]*hr_lite/vendor/turbo\.min[^>]*>}]
    expect(tag).to include('type="module"')
  end

  it "asks the host which requests come from its app" do
    HrLite.config.native_app = ->(request) { request.headers["X-Requested-With"] == "asia.example.staff" }
    get "/hr/", headers: { "HTTP_X_REQUESTED_WITH" => "asia.example.staff" }

    expect(response.body).to include("turbo-visit-control")
  ensure
    HrLite.config.native_app = HrLite::Configuration.new.native_app
  end

  it "leaves browsers without Turbo" do
    get "/hr/", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone) Mobile Safari" }

    expect(response.body).to include("Hello,")
    expect(response.body).not_to include("turbo-visit-control")
    expect(response.body).not_to include("hr_lite/vendor/turbo")
  end
end
