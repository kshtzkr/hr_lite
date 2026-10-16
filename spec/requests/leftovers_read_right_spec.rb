require "rails_helper"

RSpec.describe "Leftover screens read right", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  it "names the company board Everyone, on the tab and the page" do
    get "/hr/team"
    expect(response.body).to include(">Everyone</a>", "Everyone — today", ">People</div>")
    expect(response.body).not_to include("My team", "Team size")
  end

  it "puts Give WFH first and folds the filters until one is used" do
    create(:employee_profile, user: create(:user, name: "Dev"))
    get "/hr/admin/wfh_requests"
    expect(response.body.index("Give WFH")).to be < response.body.index(">Filter</summary>")
    expect(response.body).to include('<details class="hrl-card">')

    get "/hr/admin/wfh_requests", params: { status: "pending" }
    expect(response.body).to include('<details class="hrl-card" open>')
  end
end
