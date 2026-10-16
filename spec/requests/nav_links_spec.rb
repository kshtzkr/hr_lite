require "rails_helper"

RSpec.describe "Navigation that leads somewhere", type: :request do
  let(:hr) { user_with_roles(HrLite::Role::HR, name: "Chitra") }
  let(:employee) { user_with_roles(HrLite::Role::EMPLOYEE, name: "Meera") }

    it "hides the employee Approvals inbox until an approval flow exists" do
      sign_in employee
      get "/hr/"
      expect(response.body).not_to include('href="/hr/approvals"')

      HrLite::ApprovalFlow.create!(subject_type: "HrLite::LeaveRequest", name: "Two-step", active: true)
      get "/hr/"
      expect(response.body).to include('href="/hr/approvals"')
    end

    it "links My profile and the balance pages" do
      sign_in employee
      get "/hr/leave_requests"
      expect(response.body).to include('href="/hr/profile"').and include('href="/hr/leave_balances"')
      sign_in hr
      get "/hr/leave_requests"
      expect(response.body).to include('href="/hr/admin/leave_balances"')
    end

    it "shows Claims to whoever approves claims, and only them" do
      sign_in hr
      get "/hr/"
      expect(response.body).not_to include('href="/hr/admin/expenses"')

      finance = user_with_roles(HrLite::Role::FINANCE, name: "Farah")
      sign_in finance
      get "/hr/approvals" # Inbox opens on All; Claims is its tab
      expect(response.body).to include('href="/hr/admin/expenses"')
      expect(response.body).not_to include('href="/hr/admin/overview"')
    end

    it "links the app bar name to the profile, with no bell unless the host configures one" do
      sign_in employee
      get "/hr/"
      bar = Nokogiri::HTML(response.body).at_css(".hrl-appbar")
      expect(bar.at_css("a.hrl-appbar__user")["href"]).to eq("/hr/profile")
      expect(bar.at_css(".hrl-bell")).to be_nil
    end

    it "lists the places the tab bar cannot hold in the More sheet, led by the host's back link only when one is configured" do
      sign_in employee
      get "/hr/"
      sheet = Nokogiri::HTML(response.body).at_css(".hrl-sheet")
      expect(sheet.css(".hrl-nav__text").map { |t| t.children.first.text }).to eq([ "People", "Me", "Help" ])
      expect(sheet.at_css(".hrl-side__back")).to be_nil

      HrLite.config.back_link = { label: "Back to CMS", url: "https://cms.example.test" }
      get "/hr/"
      first = Nokogiri::HTML(response.body).at_css(".hrl-sheet > :first-child")
      expect([ first["href"], first.text ]).to eq([ "https://cms.example.test", "Back to CMS" ])
    end

    it "links a sub-screen back to its parent tab, and leaves the tabs themselves without one" do
      sign_in employee
      { "/hr/leave_balances" => "/hr/leave_requests", "/hr/holidays" => "/hr/calendar" }.each do |path, parent|
        get path
        expect(Nokogiri::HTML(response.body).at_css("a.hrl-backlink")["href"]).to eq(parent)
      end
      [ "/hr/", "/hr/attendance" ].each do |path|
        get path
        expect(Nokogiri::HTML(response.body).at_css(".hrl-backlink")).to be_nil
      end
    end

    it "gives each place a decorative icon, and names a sheet place's tabs under it" do
      sign_in employee
      get "/hr/"
      page = Nokogiri::HTML(response.body)
      expect(page.css(".hrl-side__nav a").map { |a| a.at_css("svg.hrl-icon")&.[]("aria-hidden") }.uniq).to eq([ "true" ])
      me = page.css(".hrl-sheet a").find { |a| a.at_css(".hrl-nav__text")&.children&.first&.text == "Me" }
      expect(me.at_css(".hrl-nav__hint").text).to eq("Profile, Documents, ID card, Career, Timeline")
    end

    it "loads the script that scrolls the menu to the current screen" do
      sign_in employee
      get "/hr/"
      expect(response.body).to include("hr_lite/nav")
    end

    it "marks the current screen, and lights More only when that screen sits in the sheet" do
      sign_in employee
      get "/hr/calendar"
      page = Nokogiri::HTML(response.body)
      expect(page.css('a[aria-current="page"]').map { |a| a["href"] }.uniq).to eq([ "/hr/calendar" ])
      expect(page.at_css('.hrl-tabbar > a[href="/hr/leave_requests"]')["aria-current"]).to eq("true")
      expect(page.at_css(".hrl-tabbar__more > summary")["aria-current"]).to be_nil

      get "/hr/org"
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".hrl-tabbar__more > summary")["class"]).to include("hrl-nav__link--active")
      expect(page.at_css(".hrl-tabbar__more > summary")["aria-current"]).to eq("true")

      sign_in hr
      get "/hr/admin/reports"
      expect(Nokogiri::HTML(response.body).at_css(".hrl-tabbar__more > summary")["class"]).to include("hrl-nav__link--active")
    end

    it "offers Record leave on the Leaves page to whoever can record it, and only them" do
      sign_in employee
      get "/hr/leave_requests"
      expect(response.body).not_to include("Record leave for someone")

      sign_in hr
      get "/hr/leave_requests"
      expect(response.body).to include('href="/hr/admin/leave_requests/new"')
    end

    it "tells the recorder why someone may be missing, and links the fix to whoever can make it" do
      sign_in hr
      get "/hr/admin/leave_requests/new"
      # HR edits employee profiles too (0.24.0), so it is offered the fix directly.
      expect(response.body).to include('placeholder="Start typing a name or code…"')
        .and include("Only people with an HR profile are listed.")
        .and include("Set up their profile")

      sign_in user_with_roles(HrLite::Role::LEADERSHIP, name: "Lata")
      get "/hr/admin/leave_requests/new"
      expect(response.body).to include("Set up their profile")
    end

    it "links a person's pages back to the place they came from" do
      create(:employee_profile, user: employee)
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR, HrLite::Role::LEADERSHIP, name: "Lata")
      { "/hr/admin/employees/#{HrLite::EmployeeProfile.last.id}" => "/hr/admin/employees",
        "/hr/admin/documents/for/#{employee.id}" => "/hr/admin/documents",
        "/hr/admin/attendances/#{employee.id}" => "/hr/admin/attendances",
        "/hr/id_card/#{employee.id}" => "/hr/admin/employees",
        "/hr/people/#{employee.id}/timeline" => "/hr/org" }.each do |path, parent|
        get path
        expect(Nokogiri::HTML(response.body).at_css("a.hrl-backlink")&.[]("href")).to eq(parent), path
      end
    end

    it "links a profile correction to the help desk and sets Resignation apart from Org chart" do
      create(:employee_profile, user: employee)
      sign_in employee
      get "/hr/profile"
      card = Nokogiri::HTML(response.body).at_css("section.hrl-card")
      expect(card.at_css("p a.hrl-card__link")["href"]).to eq("/hr/hr_requests/new")
      expect(card.at_css("hr + a")["href"]).to eq("/hr/resignation")
    end
end
