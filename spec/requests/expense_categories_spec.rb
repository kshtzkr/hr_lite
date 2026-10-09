require "rails_helper"

RSpec.describe "Expense categories admin", type: :request do
  let(:lead) { user_with_roles(HrLite::Role::LEADERSHIP, name: "Asha") }
  let(:staff) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

  def add(name: "Travel", cap: "", receipt: "0", active: "1")
    post "/hr/admin/expense_categories", params: { expense_category: {
      name: name, monthly_cap: cap, receipt_required: receipt, active: active
    } }
  end

  describe "as leadership" do
    before { sign_in lead }

    it "says no claim is possible until a category exists, and ticks receipt by default" do
      get "/hr/admin/expense_categories"
      expect(response.body).to include("No categories yet")

      get "/hr/admin/expense_categories/new"
      expect(response.body).to match(/checked="checked" name="expense_category\[receipt_required\]"/)
    end

    it "adds a category an employee can then claim against" do
      add(cap: "5000")
      category = HrLite::ExpenseCategory.last
      expect(category).to have_attributes(name: "Travel", monthly_cap: BigDecimal("5000"),
                                          receipt_required: false, active: true)
      get "/hr/admin/expense_categories"
      expect(response.body).to include("Travel")

      sign_in staff
      get "/hr/expenses/new"
      expect(response.body).to include(">Travel (₹5,000.00 left this month)</option>")
      expect {
        post "/hr/expenses", params: { expense: { category_id: category.id, amount: "1200",
                                                  spent_on: Date.current.to_s, description: "Cab" } }
      }.to change(HrLite::Expense, :count).by(1)
    end

    it "treats a blank cap as uncapped" do
      add
      expect(HrLite::ExpenseCategory.last).to be_uncapped
    end

    it "retires a category by unticking active, and the claim form stops offering it" do
      add
      category = HrLite::ExpenseCategory.last
      get "/hr/admin/expense_categories/#{category.id}/edit"
      expect(response).to have_http_status(:ok)

      patch "/hr/admin/expense_categories/#{category.id}", params: { expense_category: { active: "0" } }
      expect(category.reload.active).to be(false)

      sign_in staff
      get "/hr/expenses/new"
      expect(response.body).not_to include(">Travel</option>")
    end

    it "refuses a blank name on create and on update" do
      expect { add(name: "") }.not_to change(HrLite::ExpenseCategory, :count)
      expect(response).to have_http_status(:unprocessable_entity)

      add
      patch "/hr/admin/expense_categories/#{HrLite::ExpenseCategory.last.id}",
            params: { expense_category: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "refuses somebody without profile.manage" do
    sign_in staff
    add
    expect(HrLite::ExpenseCategory.count).to eq(0)
    expect(response).to redirect_to("/hr/")
  end
end
