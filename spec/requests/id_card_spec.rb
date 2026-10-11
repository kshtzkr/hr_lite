require "rails_helper"

RSpec.describe "Employee ID card", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Ananya Sharma") }
  let(:peer) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Peer") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:profile) do
    create(:employee_profile, user: employee, employee_code: "ESA-000427", designation: "Senior Trip Manager",
                              department: "Operations", date_of_joining: Date.new(2024, 3, 12),
                              blood_group: "B+", emergency_contact: "+91 98100 12345")
  end

  def image(type = "image/png", name = "me.png", body = "\x89PNG\r\n\x1A\n".b)
    Rack::Test::UploadedFile.new(StringIO.new(body), type, original_filename: name)
  end

  it "shows the employee their own card, front and back" do
    sign_in employee
    get "/hr/id_card"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ESA-000427", "Senior Trip Manager", "Operations", "B+", "Mar 2024",
                                     "+91 98100 12345", "<svg")
  end

  it "puts the office address and phone in the QR, and nothing else" do
    allow(HrLite.config).to receive(:company)
      .and_return(-> { { name: "Earthly", brand: "escapes.asia", address: "Sector 62, Noida", phone: "+91 99901 19989" } })
    expect(RQRCode::QRCode).to receive(:new).with("escapes.asia\nSector 62, Noida\n+91 99901 19989").and_call_original
    sign_in employee

    get "/hr/id_card"
    expect(response.body).to include("or call +91 99901 19989")
  end

  it "offers a Share image with the photo served from this site" do
    profile.photo.attach(io: StringIO.new("\x89PNG\r\n\x1A\n".b), filename: "me.png", content_type: "image/png")
    sign_in employee
    get "/hr/id_card"

    expect(response.body).to include(%(data-hrl-share="id-card-ESA-000427.png"), "hr_lite/share", "/rails/active_storage/blobs/proxy/")
    expect(response.body).to include("data-hrl-photo-input", "data-hrl-photo-zoom", "hr_lite/photo_crop")
  end

  it "lets HR open a colleague's card to print it" do
    sign_in hr
    get "/hr/id_card/#{employee.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ESA-000427")
    expect(response.body).not_to include("Upload photo")
  end

  it "refuses a colleague without HR reach" do
    sign_in peer
    get "/hr/id_card/#{employee.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "says so when there is no HR profile yet" do
    sign_in peer
    get "/hr/id_card"

    expect(response.body).to include("has not been set up yet")
  end

  describe "changing the photo" do
    before { sign_in employee }

    it "attaches the photo and records who changed it" do
      patch "/hr/id_card/photo", params: { photo: image }

      expect(profile.reload.photo).to be_attached
      expect(HrLite::AuditLog.where(action: "id_card.photo_changed", subject_id: profile.id)).to exist
    end

    it "changes nothing but the photo" do
      patch "/hr/id_card/photo", params: { photo: image, blood_group: "O-", employee_profile: { blood_group: "O-" } }

      expect(profile.reload.blood_group).to eq("B+")
    end

    it "refuses a file a browser could run" do
      patch "/hr/id_card/photo", params: { photo: image("image/svg+xml", "x.svg", "<svg onload=alert(1)>") }

      expect(flash[:alert]).to include("JPG, PNG or WebP")
      expect(profile.reload.photo).not_to be_attached
    end

    it "refuses a photo over the size cap" do
      stub_const("HrLite::EmployeeProfile::PHOTO_MAX_BYTES", 4)
      patch "/hr/id_card/photo", params: { photo: image }

      expect(flash[:alert]).to include("must be under")
      expect(profile.reload.photo).not_to be_attached
    end

    it "is refused to someone without a profile" do
      sign_in peer
      patch "/hr/id_card/photo", params: { photo: image }

      expect(response).to have_http_status(:not_found)
    end
  end

  it "keeps blood group to the eight standard groups" do
    expect(profile.update(blood_group: "Q+")).to be(false)
    expect(profile.update(blood_group: "")).to be(true)
  end
end
