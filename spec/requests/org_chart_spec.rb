require "rails_helper"

RSpec.describe "Org chart", type: :request do
  let(:director) { create(:user, name: "Asha Director") }
  let(:manager) { create(:user, name: "Rohan Manager") }
  let(:employee) { create(:user, name: "Meera Field") }

  let!(:director_profile) do
    create(:employee_profile, user: director, designation: "Director", department: "Leadership")
  end
  let!(:manager_profile) do
    create(:employee_profile, user: manager, designation: "Ops Manager", manager_id: director.id)
  end
  let!(:employee_profile) do
    create(:employee_profile, user: employee, designation: "Travel Consultant",
                              manager_id: manager.id)
  end

  before { sign_in employee }

  it "shows the whole tree to any employee, nested under the right managers" do
    get "/hr/org"
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Asha Director").and include("Rohan Manager").and include("Meera Field")
    # Nesting order INSIDE the tree (the chain card above also names bosses).
    tree = body[body.index("Who reports to whom")..]
    expect(tree.index("Asha Director")).to be < tree.index("Rohan Manager")
    expect(tree.index("Rohan Manager")).to be < tree.index("Meera Field")
  end

  it "labels the viewer's own reporting line L1/L2 up to the top" do
    get "/hr/org"
    expect(response.body).to include("L1 · Rohan Manager").and include("L2 · Asha Director")
    expect(response.body).to include("hrl-tree__card--me")
  end

  it "never leaks salary or identity data" do
    create(:salary_structure, user: manager, basic: BigDecimal("123456"))
    manager_profile.update!(pan_number: "ABCDE1234F", bank_account_number: "9998887776665")

    get "/hr/org"
    expect(response.body).not_to include("123456")
    expect(response.body).not_to include("ABCDE1234F")
    expect(response.body).not_to include("6665")
  end

  it "hides exited staff and promotes their reports to visible roots" do
    manager_profile.update!(date_of_exit: Date.current - 1)
    get "/hr/org"
    expect(response.body).not_to include("Rohan Manager")
    expect(response.body).to include("Meera Field") # still on the chart
  end

  it "tops out cleanly for someone with no manager" do
    sign_in director
    get "/hr/org"
    expect(response.body).to include("top of the organisation")
  end

  describe "manager assignment guardrails" do
    it "rejects self-management and loops" do
      expect(build(:employee_profile, user: create(:user), manager_id: nil)).to be_valid

      self_managed = employee_profile.tap { |p| p.manager_id = employee.id }
      expect(self_managed).not_to be_valid
      expect(self_managed.errors[:manager_id].join).to include("yourself")

      # employee reports to manager reports to director; director -> employee = loop
      looped = director_profile.tap { |p| p.manager_id = employee.id }
      expect(looped).not_to be_valid
      expect(looped.errors[:manager_id].join).to include("loop")
    end

    it "leadership sets the manager through the employee form" do
      leader = create(:user, email: "lead@x.test")
      HrLite.config.leadership_emails = [ "lead@x.test" ]
      sign_in leader

      patch "/hr/admin/employees/#{employee_profile.id}", params: {
        employee_profile: { manager_id: director.id }
      }
      expect(employee_profile.reload.manager_id).to eq(director.id)

      get "/hr/admin/employees/#{employee_profile.id}"
      expect(response.body).to include("Reports to").and include("Asha Director")
    end
  end

  it "shows the reporting line on the employee's own profile" do
    get "/hr/profile"
    expect(response.body).to include("Rohan Manager (your L1)")
  end
end
