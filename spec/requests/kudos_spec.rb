require "rails_helper"

RSpec.describe "Kudos", type: :request do
  let(:user) { create(:user, name: "Giver") }
  let(:teammate) { create(:user, name: "Asha") }

  before { sign_in user }

  describe "GET /hr/kudos" do
    it "requires sign-in" do
      sign_out
      get "/hr/kudos"
      expect(response).to have_http_status(:unauthorized)
    end

    it "shows the wall to any signed-in user, paginated at 25" do
      26.times { create(:kudo, giver: teammate) }
      get "/hr/kudos"
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/hrl-feed__item/).size).to eq(25)
      expect(response.body).to include("Page 1 of 2")
    end
  end

  describe "POST /hr/kudos" do
    it "creates the kudo, mention rows and notifications" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }

      expect {
        post "/hr/kudos", params: { kudo: { message: "Star turn @[Asha](#{teammate.id})", badge: "team_player" } }
      }.to change(HrLite::Kudo, :count).by(1)
        .and change(HrLite::KudoMention, :count).by(1)

      expect(response).to redirect_to("/hr/kudos")
      kudo = HrLite::Kudo.last
      expect(kudo.giver).to eq(user)
      expect(kudo.mentioned_users).to eq([ teammate ])
      expect(bells.map { |b| b[:user] }).to eq([ teammate ])
    end

    it "re-renders with errors for an invalid kudo" do
      post "/hr/kudos", params: { kudo: { message: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("prevented saving")
    end
  end

  describe "DELETE /hr/kudos/:id" do
    it "lets the giver remove within the window" do
      kudo = create(:kudo, giver: user)
      delete "/hr/kudos/#{kudo.id}"
      expect(HrLite::Kudo.exists?(kudo.id)).to be(false)
    end

    it "refuses others' kudos" do
      kudo = create(:kudo, giver: teammate)
      delete "/hr/kudos/#{kudo.id}"
      expect(response).to redirect_to("/hr/kudos")
      expect(flash[:alert]).to be_present
      expect(HrLite::Kudo.exists?(kudo.id)).to be(true)
    end

    it "refuses the giver after the window" do
      kudo = create(:kudo, giver: user)
      travel_to(16.minutes.from_now) do
        delete "/hr/kudos/#{kudo.id}"
        expect(HrLite::Kudo.exists?(kudo.id)).to be(true)
      end
    end

    it "lets an admin moderate any time" do
      sign_in create(:user, :admin)
      kudo = create(:kudo, giver: teammate)
      travel_to(1.day.from_now) do
        delete "/hr/kudos/#{kudo.id}"
        expect(HrLite::Kudo.exists?(kudo.id)).to be(false)
      end
    end
  end

  describe "XSS safety" do
    it "escapes hostile message content and unmatched markers" do
      create(:kudo, giver: user, message: "<script>alert(1)</script> @[Fake<b>](99999)")
      get "/hr/kudos"
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;")
      expect(response.body).not_to include("Fake<b>")
    end

    it "renders matched mentions as chips with the current display name" do
      kudo = create(:kudo, giver: user, message: "Hi @[Old Name](#{teammate.id})")
      kudo.register_mentions!
      teammate.update!(name: "New Name")
      get "/hr/kudos"
      expect(response.body).to include(%(<span class="hrl-mention">@New Name</span>))
    end
  end
end
