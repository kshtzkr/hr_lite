require "rails_helper"

RSpec.describe "The money tier stands apart from leadership", type: :request do
  let(:employee) { create(:user, name: "Meera", email: "meera@example.com") }
  # Governs people and policy, but is NOT on the money list.
  let(:leader) { create(:user, name: "Khushboo", email: "khushboo@example.com", admin: true) }
  # On the money list only — the payroll operator who governs nothing else.
  let(:payroll_operator) { create(:user, name: "Dev", email: "dev@example.com") }

  before do
    HrLite.config.leadership_emails = [ leader.email ]
    HrLite.config.superadmin_emails = [ payroll_operator.email ]
  end

  it "lets a superadmin who is absent from leadership_emails reach payroll" do
    sign_in payroll_operator
    get "/hr/admin/payroll_runs"

    expect(response).to have_http_status(:ok)
  end

  it "still keeps payroll away from leadership who are not on the money list" do
    sign_in leader
    get "/hr/admin/payroll_runs"

    expect(response).to redirect_to("/hr/")
  end

  it "shows the Payroll nav item to a superadmin who is not in leadership" do
    sign_in payroll_operator
    get "/hr/"

    expect(response.body).to include("Payroll")
  end

  describe "the audit trail" do
    let!(:appraisal) do
      HrLite::Current.actor = payroll_operator
      create(:appraisal, user: employee, reviewer: payroll_operator,
                         strengths: "Runs the Bali desk single-handed")
    end

    it "hides appraisal rows from leadership outside the money tier" do
      sign_in leader
      get "/hr/admin/audit_logs"

      expect(response.body).not_to include("Runs the Bali desk single-handed")
      expect(response.body).not_to include("Appraisal")
    end

    # The audit screen itself is a governance surface, so reading money-tier
    # rows takes both hats — which is how the owner's own accounts are set up.
    it "shows them to someone on both lists" do
      both = create(:user, name: "Kshitiz", email: "kshitiz@example.com", admin: true)
      HrLite.config.leadership_emails = [ leader.email, both.email ]
      HrLite.config.superadmin_emails = [ payroll_operator.email, both.email ]

      sign_in both
      get "/hr/admin/audit_logs"

      expect(response.body).to include("Appraisal")
    end
  end

  it "keeps appraisal review text out of the policy.changed leadership email" do
    HrLite::Current.actor = payroll_operator
    published = nil
    allow(HrLite::Notifications).to receive(:publish).and_wrap_original do |original, event, **kwargs|
      published = kwargs if event.to_s == "policy.changed"
      original.call(event, **kwargs)
    end

    create(:appraisal, user: employee, reviewer: payroll_operator,
                       strengths: "Runs the Bali desk single-handed")

    expect(published).to be_present
    expect(published[:diff]).to be_nil
  end
end
