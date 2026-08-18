require "rails_helper"

# 0.14.0 shipped the Document model, table and expiry job with NO controller,
# route or view — an employee could not upload a passport and HR could not
# verify one. These pin the screens that were missing.
RSpec.describe "Documents over HTTP", type: :request do
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:owner) { user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner") }

  def upload(user:, category: "pan", title: "PAN card", **extra)
    HrLite::Document.create!(
      { user_id: user.id, category: category, title: title,
        file: fixture_file }.merge(extra)
    )
  end

  def fixture_file
    { io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "scan.pdf", content_type: "application/pdf" }
  end

  describe "an employee's own documents" do
    before { sign_in employee }

    it "uploads one and lists it" do
      expect {
        post "/hr/documents", params: {
          document: { category: "pan", title: "PAN card", number: "ABCDE1234F",
                      file: Rack::Test::UploadedFile.new(
                        StringIO.new("%PDF-1.4\n"), "application/pdf", original_filename: "pan.pdf"
                      ) }
        }
      }.to change(HrLite::Document, :count).by(1)

      get "/hr/documents"
      expect(response.body).to include("PAN card")
    end

    it "refuses a file type that can carry script" do
      post "/hr/documents", params: {
        document: { category: "other", title: "Sneaky",
                    file: Rack::Test::UploadedFile.new(
                      StringIO.new("<svg onload=alert(1)>"), "image/svg+xml",
                      original_filename: "x.svg"
                    ) }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(HrLite::Document.count).to eq(0)
    end

    it "removes an unverified document but not a verified one" do
      doc = upload(user: employee)
      delete "/hr/documents/#{doc.id}"
      expect(HrLite::Document.exists?(doc.id)).to be(false)

      verified = upload(user: employee, title: "Passport", category: "passport")
      verified.verify!(actor: hr)
      delete "/hr/documents/#{verified.id}"

      expect(flash[:alert]).to include("verified")
      expect(HrLite::Document.exists?(verified.id)).to be(true)
    end

    it "never lists somebody else's" do
      upload(user: hr, title: "Chitra PAN")
      get "/hr/documents"
      expect(response.body).not_to include("Chitra PAN")
    end
  end

  # The file is the sensitive part. Reaching the row is not the same as being
  # allowed to open the scan.
  describe "downloading" do
    it "lets the owner open their own" do
      doc = upload(user: employee)
      sign_in employee
      get "/hr/documents/#{doc.id}/download"
      expect(response).to have_http_status(:redirect)
    end

    it "404s a stranger, rather than admitting the document exists" do
      doc = upload(user: employee)
      stranger = user_with_roles(HrLite::Role::EMPLOYEE)
      sign_in stranger

      get "/hr/documents/#{doc.id}/download"
      expect(response).to have_http_status(:not_found)
    end

    it "keeps a self-only document away from HR" do
      doc = upload(user: employee, category: "other", title: "Private", visibility: "self")
      sign_in hr

      get "/hr/documents/#{doc.id}/download"
      expect(response).to have_http_status(:not_found)
    end

    it "audits every download, because a file leaves the building" do
      doc = upload(user: employee)
      sign_in employee

      expect {
        get "/hr/documents/#{doc.id}/download"
      }.to change { HrLite::AuditLog.where(action: "document.downloaded").count }.by(1)
    end
  end

  describe "HR's side" do
    before { sign_in hr }

    it "lists what is waiting and verifies one it can open" do
      doc = upload(user: employee, category: "offer_letter", title: "Offer letter")
      get "/hr/admin/documents"
      expect(response.body).to include("Meera", "Offer letter")

      post "/hr/admin/documents/#{doc.id}/verify"
      expect(doc.reload).to be_verified
      expect(doc.verified_by_id).to eq(hr.id)
    end

    # Attesting to a scan you are not allowed to look at is not verification.
    # An identity document defaults to the money tier, and HR running the
    # company's leave does not make somebody's Aadhaar theirs to open.
    it "cannot verify an identity document it may not open" do
      pan = upload(user: employee, category: "pan", title: "PAN card")
      expect(pan.visibility).to eq("money")

      post "/hr/admin/documents/#{pan.id}/verify"

      expect(response).to have_http_status(:not_found)
      expect(pan.reload).to be_pending
    end

    it "lets the money tier verify it" do
      pan = upload(user: employee, category: "pan", title: "PAN card")
      sign_in owner

      post "/hr/admin/documents/#{pan.id}/verify"
      expect(pan.reload).to be_verified
    end

    it "will not reject without saying what is wrong" do
      doc = upload(user: employee, category: "offer_letter", title: "Offer letter")
      post "/hr/admin/documents/#{doc.id}/reject", params: { note: "  " }

      expect(flash[:alert]).to include("re-upload")
      expect(doc.reload).to be_pending
    end

    it "rejects with a reason, and the employee sees why" do
      doc = upload(user: employee, category: "offer_letter", title: "Offer letter")

      post "/hr/admin/documents/#{doc.id}/reject", params: { note: "Page 2 is missing" }

      expect(doc.reload.verification).to eq("rejected")
      expect(doc.verification_note).to eq("Page 2 is missing")

      sign_in employee
      get "/hr/documents"
      expect(response.body).to include("Page 2 is missing")
    end

    it "shows one person's file and names what is missing" do
      upload(user: employee, category: "pan")
      get "/hr/admin/documents/for/#{employee.id}"

      expect(response.body).to include("PAN card")
      # aadhaar, passport and bank have not been uploaded
      expect(response.body).to include("Aadhaar")
    end

    it "turns away an employee entirely" do
      sign_in employee
      get "/hr/admin/documents"
      expect(response).to redirect_to("/hr/")
    end
  end
end
