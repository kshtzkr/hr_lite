require "rails_helper"

RSpec.describe "Mention search", type: :request do
  it "requires sign-in" do
    get "/hr/users/search", params: { q: "as" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns value/text pairs from the configured source" do
    asha = create(:user, name: "Asha Rao")
    create(:user, name: "Zed")
    sign_in asha

    get "/hr/users/search", params: { q: "asha" }
    expect(response.parsed_body).to eq([ { "value" => asha.id, "text" => "Asha Rao" } ])
  end

  it "honours a host-overridden mentionable_users lambda" do
    user = create(:user, name: "Only Me")
    HrLite.config.mentionable_users = ->(_q) { User.where(id: user.id) }
    sign_in user

    get "/hr/users/search", params: { q: "whatever" }
    expect(response.parsed_body.map { |r| r["text"] }).to eq([ "Only Me" ])
  end
end
