require "rails_helper"

# Your own pay and record are for someone else to change (pairs with the 404 in hr_lite #126).
RSpec.describe "Own employee page", type: :request do
  it "offers no Edit, salary or Offboard on your own page, and still does on someone else's" do
    hr = user_with_roles(HrLite::Role::HR, name: "Chitra")
    mine = create(:employee_profile, user: hr)
    theirs = create(:employee_profile)
    sign_in hr

    get "/hr/admin/employees/#{mine.id}"
    expect(response.body).not_to include("Offboard employee", "edit_admin", %(href="/hr/admin/employees/#{mine.id}/edit"))

    get "/hr/admin/employees/#{theirs.id}"
    expect(response.body).to include("Offboard employee", %(href="/hr/admin/employees/#{theirs.id}/edit"))
  end

  it "still offers Super Admin the Edit button on their own page" do
    owner = user_with_roles(HrLite::Role::SUPER_ADMIN, name: "Owner")
    mine = create(:employee_profile, user: owner)
    sign_in owner

    get "/hr/admin/employees/#{mine.id}"
    expect(response.body).to include(%(href="/hr/admin/employees/#{mine.id}/edit"))
  end
end
