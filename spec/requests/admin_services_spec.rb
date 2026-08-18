require "rails_helper"

# The admin side of everything built since 0.11.0 — the half that turns an
# engine into a loop somebody can actually run a company on.
RSpec.describe "Admin services", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  describe "deciding a claim" do
    let(:category) { HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false) }
    let!(:claim) do
      expense = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 1_500,
                                        spent_on: Date.current, description: "Cab")
      expense.submit!(actor: employee)
      expense
    end

    it "approves, then records the payroll month it was paid with" do
      sign_in finance
      post "/hr/admin/expenses/#{claim.id}/approve"
      expect(claim.reload).to be_approved

      post "/hr/admin/expenses/#{claim.id}/reimburse", params: { period_month: "2027-06" }
      expect(claim.reload).to be_reimbursed
      expect(claim.reimbursed_in).to eq(Date.new(2027, 6, 1))
    end

    it "insists on a reason to reject" do
      sign_in finance
      post "/hr/admin/expenses/#{claim.id}/reject", params: { decision_note: "" }

      expect(flash[:alert]).to include("note is required")
      expect(claim.reload).to be_submitted
    end

    it "rejects with the reason, and the reason reaches the claimant" do
      sign_in finance
      post "/hr/admin/expenses/#{claim.id}/reject",
           params: { decision_note: "Take the metro next time" }

      expect(claim.reload).to be_rejected
      expect(claim.decision_note).to eq("Take the metro next time")
    end

    it "will not reimburse something nobody approved" do
      sign_in finance
      post "/hr/admin/expenses/#{claim.id}/reimburse", params: { period_month: "2027-06" }

      expect(flash[:alert]).to include("Only an approved claim")
    end

    # HR runs the people screens but does not decide money.
    it "is closed to HR" do
      sign_in hr
      get "/hr/admin/expenses"
      expect(response).to redirect_to("/hr/")
    end
  end

  describe "the help desk" do
    let!(:request) do
      HrLite::HrRequest.create!(user_id: employee.id, category: "salary_certificate",
                                subject: "Certificate for a visa")
    end

    it "answers, and the answer reaches the person who asked" do
      sign_in hr
      post "/hr/admin/hr_requests/#{request.id}/resolve",
           params: { resolution: "Signed and emailed." }

      expect(request.reload).to be_resolved
      expect(request.resolution).to eq("Signed and emailed.")
    end

    it "refuses to resolve with an empty answer" do
      sign_in hr
      post "/hr/admin/hr_requests/#{request.id}/resolve", params: { resolution: "  " }

      expect(flash[:alert]).to include("Write an answer")
      expect(request.reload).to be_open
    end

    it "hands a request to somebody" do
      sign_in hr
      post "/hr/admin/hr_requests/#{request.id}/assign", params: { assignee_id: hr.id }

      expect(request.reload).to be_in_progress
      expect(request.assigned_to_id).to eq(hr.id)
    end
  end

  describe "assets" do
    let!(:laptop) do
      HrLite::Asset.create!(name: "MacBook Air", category: "laptop", serial_number: "C02X1")
    end

    before { sign_in hr }

    it "hands one over and takes it back with its condition" do
      post "/hr/admin/assets/#{laptop.id}/assign", params: { user_id: employee.id }

      expect(laptop.reload).to be_assigned
      expect(laptop.holder).to eq(employee)

      post "/hr/admin/assets/#{laptop.id}/take_back",
           params: { condition_note: "Screen scratched", status: "damaged" }

      expect(laptop.reload).to be_damaged
      expect(laptop.holder).to be_nil
      expect(laptop.asset_assignments.sole.condition_note).to eq("Screen scratched")
    end

    # Two open assignments would mean the laptop is in two places.
    it "refuses to hand out something already with somebody" do
      post "/hr/admin/assets/#{laptop.id}/assign", params: { user_id: employee.id }
      post "/hr/admin/assets/#{laptop.id}/assign", params: { user_id: hr.id }

      expect(flash[:alert]).to include("already with somebody")
      expect(laptop.reload.holder).to eq(employee)
    end

    it "refuses to take back something nobody has" do
      post "/hr/admin/assets/#{laptop.id}/take_back"
      expect(flash[:alert]).to include("not with anybody")
    end

    it "adds one, and refuses a duplicate serial" do
      expect {
        post "/hr/admin/assets", params: { asset: { name: "iPhone", category: "phone",
                                                    serial_number: "IP-1" } }
      }.to change(HrLite::Asset, :count).by(1)

      post "/hr/admin/assets", params: { asset: { name: "Another", category: "phone",
                                                  serial_number: "IP-1" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "lists what is still out" do
      post "/hr/admin/assets/#{laptop.id}/assign", params: { user_id: employee.id }
      get "/hr/admin/assets"

      expect(response.body).to include("Currently out", "MacBook Air", "Meera")
    end
  end

  describe "joining and leaving checklists" do
    before { HrLite::ChecklistTemplate.seed_defaults! }

    it "opens the joining list when a profile is created" do
      profile = create(:employee_profile, user: employee)

      items = HrLite::ChecklistItem.for_kind("onboarding").where(user_id: employee.id)
      expect(items.map(&:title)).to include("Collect signed offer letter")
      expect(items.first.due_on).to eq(profile.date_of_joining)
    end

    it "opens the leaving list when somebody is offboarded" do
      profile = create(:employee_profile, user: employee)
      sign_in user_with_roles(HrLite::Role::LEADERSHIP, name: "Boss")

      post "/hr/admin/employees/#{profile.id}/offboard",
           params: { date_of_exit: Date.current.to_s }

      titles = HrLite::ChecklistItem.for_kind("offboarding").where(user_id: employee.id)
                                    .map(&:title)
      expect(titles).to include("Collect laptop and accessories",
                                "Revoke email and system access")
    end

    it "does not double the list when it is opened again" do
      create(:employee_profile, user: employee)
      before_count = HrLite::ChecklistItem.where(user_id: employee.id).count
      HrLite::ChecklistItem.open_for!(employee, kind: "onboarding", anchor_date: Date.current)

      expect(HrLite::ChecklistItem.where(user_id: employee.id).count).to eq(before_count)
    end

    it "ticks a step off and can reopen it" do
      create(:employee_profile, user: employee)
      item = HrLite::ChecklistItem.where(user_id: employee.id).first
      sign_in hr

      post "/hr/admin/checklists/#{item.id}/complete", params: { note: "Filed" }
      expect(item.reload).to be_done
      expect(item.completed_by_id).to eq(hr.id)

      post "/hr/admin/checklists/#{item.id}/reopen"
      expect(item.reload).not_to be_done
    end

    it "shows what is overdue" do
      create(:employee_profile, user: employee)
      HrLite::ChecklistItem.where(user_id: employee.id).update_all(due_on: Date.current - 5)
      sign_in hr

      get "/hr/admin/checklists"
      expect(response.body).to include("overdue", "Overdue")
    end

    it "never blocks creating an employee if the checklist fails" do
      allow(HrLite::ChecklistItem).to receive(:open_for!).and_raise("boom")

      expect { create(:employee_profile, user: employee) }.not_to raise_error
    end
  end
end

RSpec.describe "Admin index screens", type: :request, no_legacy_bridge: true do
  let!(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let!(:finance) { user_with_roles(HrLite::Role::FINANCE, name: "Fin") }
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "lists claims by status, submitted first" do
    category = HrLite::ExpenseCategory.create!(name: "Travel", receipt_required: false)
    claim = HrLite::Expense.create!(user_id: employee.id, category: category, amount: 800,
                                    spent_on: Date.current, description: "Bus")
    claim.submit!(actor: employee)
    sign_in finance

    get "/hr/admin/expenses"
    expect(response.body).to include("Meera", "Travel")

    get "/hr/admin/expenses", params: { status: "approved" }
    expect(response.body).to include("Nothing approved")
  end

  it "lists desk requests and opens one" do
    request = HrLite::HrRequest.create!(user_id: employee.id, category: "other",
                                        subject: "A question")
    sign_in hr

    get "/hr/admin/hr_requests"
    expect(response.body).to include("A question", "Meera")

    get "/hr/admin/hr_requests/#{request.id}"
    expect(response.body).to include("Answer", "What you did")
  end

  it "opens the add-asset form" do
    sign_in hr
    get "/hr/admin/assets/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Serial number")
  end

  it "keeps the desk closed to somebody who cannot run it" do
    sign_in employee
    get "/hr/admin/hr_requests"
    expect(response).to redirect_to("/hr/")
  end

  it "keeps assets closed to somebody who cannot manage them" do
    sign_in employee
    get "/hr/admin/assets"
    expect(response).to redirect_to("/hr/")
  end
end

RSpec.describe "Asset and checklist model guards", no_legacy_bridge: true do
  let!(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  it "lists everything still out with one person" do
    laptop = HrLite::Asset.create!(name: "Laptop", category: "laptop")
    phone = HrLite::Asset.create!(name: "Phone", category: "phone")
    laptop.assign_to!(employee)
    phone.assign_to!(employee)
    phone.return!

    expect(HrLite::Asset.outstanding_for(employee)).to contain_exactly(laptop)
  end

  it "refuses a return dated before the handover" do
    laptop = HrLite::Asset.create!(name: "Laptop", category: "laptop")
    laptop.assign_to!(employee, on: Date.current)
    assignment = laptop.live_assignment
    assignment.returned_on = Date.current - 1

    expect(assignment).not_to be_valid
    expect(assignment.errors[:returned_on].join).to include("before the day it was handed over")
  end

  it "refuses a checklist step owned by a permission nobody declared" do
    template = HrLite::ChecklistTemplate.new(kind: "onboarding", title: "X",
                                             owner_permission: "not.a.permission")
    expect(template).not_to be_valid
  end

  it "seeds the default steps once" do
    HrLite::ChecklistTemplate.seed_defaults!
    expect(HrLite::ChecklistTemplate.seed_defaults!).to be_empty
  end
end
