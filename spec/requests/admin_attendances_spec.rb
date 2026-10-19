require "rails_helper"

RSpec.describe "Admin attendances", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:employee) { create(:user, name: "Asha") }

  describe "authorization" do
    it "blocks employees from the team view" do
      sign_in employee
      get "/hr/admin/attendances"
      expect(response).to redirect_to("/hr/")
    end

    it "admits admins and leadership" do
      sign_in admin
      get "/hr/admin/attendances"
      expect(response).to have_http_status(:ok)

      HrLite.config.leadership_emails = [ "lead@x.test" ]
      sign_in create(:user, email: "lead@x.test")
      get "/hr/admin/attendances"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "penalty hours" do
    before do
      HrLite.config.attendance_slots = true
      sign_in admin
    end

    it "totals a person's hours on the team view and their page, and lets HR remove some with a reason" do
      record = create(:attendance_record, :checked_in, user: employee, date: Date.current - 1)
      HrLite::AttendancePenalty.create!(user_id: employee.id, date: Date.current - 1, minutes: 6000, reason: "late", attendance_record: record)
      get "/hr/admin/attendances"
      expect(response.body).to include("Penalties 100h 00m · 10 days")

      path = "/hr/admin/attendances/#{employee.id}/remove_penalty_hours"
      post path, params: { hours: "50", reason: " " }
      expect(flash[:alert]).to eq("A reason is required.")
      post path, params: { hours: "101", reason: "x" }
      expect(flash[:alert]).to eq("Remove between 0.5h and 100h.")
      post path, params: { hours: "50", reason: "Genuine: hospital visits" }
      expect(flash[:notice]).to eq("Removed 50h of penalties.")
      expect(HrLite::AuditLog.where(action: "attendance.penalty_hours_removed").count).to eq(1)

      get "/hr/admin/attendances/#{employee.id}"
      expect(response.body).to include("50h 00m</strong> held · 5 days", "Removed 50h 00m", "Genuine: hospital visits", "Remove hours")
    end
  end

  describe "GET /hr/admin/attendances (day view)" do
    before { sign_in admin }

    it "lists every employee with punch state and flags" do
      create(:attendance_record, :checked_in, :flagged, user: employee, date: Date.current)
      get "/hr/admin/attendances"

      expect(response.body).to include("Asha").and include("Flagged").and include("No punch")
      expect(response.body).to include("Flagged</span> <span class=\"hrl-small\">Check-in without GPS (denied)</span>")
        .and include(%(aria-label="Previous day, #{(Date.current - 1).strftime('%A %-d %B')}"))
    end

    it "walks to other dates and falls back on garbage" do
      get "/hr/admin/attendances", params: { date: (Date.current - 3).to_s }
      expect(response.body).to include((Date.current - 3).strftime("%d %B %Y"))

      get "/hr/admin/attendances", params: { date: "garbage" }
      expect(response.body).to include(Date.current.strftime("%d %B %Y"))
    end
  end

  describe "GET /hr/admin/attendances/:user_id (month + fix form)" do
    before { sign_in admin }

    it "shows the month grid and a fix form for ?date" do
      create(:attendance_record, :checked_out, user: employee, date: Date.current - 1)
      get "/hr/admin/attendances/#{employee.id}", params: { date: (Date.current - 1).to_s }

      expect(response.body).to include("Fix #{(Date.current - 1).strftime('%A, %d %B')}")
        .and include("regularization_note")
    end

    it "shows today without a punch as Today and leaves it out of the absent count" do
      travel_to(Date.new(2026, 10, 8)) do # Thu; Oct 1, 2, 5, 6, 7 are past working days
        get "/hr/admin/attendances/#{employee.id}"
        cell = Nokogiri::HTML(response.body).at_css('[aria-label="8 Oct, Today, not checked in yet"]')
        expect(cell["class"].split).not_to include("hrl-mgrid__day--absent")
        expect(response.body).to include('aria-label="Absent 5 days"')
      end
    end

    it "links each day up to today to its fix form" do
      travel_to(Date.new(2026, 10, 8)) do
        get "/hr/admin/attendances/#{employee.id}"
        expect(response.body).to include("date=2026-10-08&amp;month=2026-10#regularize")
        expect(response.body).not_to include("date=2026-10-09")
      end
    end
  end

  describe "PATCH /hr/admin/attendances/:user_id (regularization)" do
    before { sign_in admin }

    let(:date) { Date.current.prev_occurring(:wednesday) } # a past weekday: leave on a weekend is refused

    it "requires a note" do
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: date.to_s, attendance_record: { check_in_at: "#{date}T09:30", regularization_note: " " }
      }
      expect(flash[:alert]).to include("note is required")
      expect(HrLite::AttendanceRecord.count).to eq(0)
    end

    it "creates the fixed record, audits it and notifies the employee" do
      bells = []
      HrLite.config.notify = ->(**kw) { bells << kw }

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "#{date}T09:30", check_out_at: "#{date}T18:00",
                               status: "present", regularization_note: "Forgot phone at home" }
        }
      }.to change(HrLite::AttendanceRecord, :count).by(1)
        .and change(HrLite::AuditLog, :count).by(1)

      record = HrLite::AttendanceRecord.last
      expect(record.regularized_by_id).to eq(admin.id)
      expect(record.regularization_note).to eq("Forgot phone at home")
      expect(bells.map { |b| b[:kind] }).to include("attendance.regularized")
      expect(bells.find { |b| b[:kind] == "attendance.regularized" }[:user]).to eq(employee)
    end

    it "refuses a fix on a day covered by approved full-day leave" do
      create(:leave_request, :approved, user: employee, start_date: date, end_date: date)
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: date.to_s, attendance_record: { check_in_at: "#{date}T09:30", regularization_note: "Forgot phone" }
      }
      expect(flash[:alert]).to eq("The day is covered by approved leave — cancel the leave first.")
      expect(HrLite::AttendanceRecord.count).to eq(0)
    end

    it "removes the punch when both times are cleared" do
      create(:attendance_record, :checked_in, user: employee, date: date)

      expect {
        patch "/hr/admin/attendances/#{employee.id}", params: {
          date: date.to_s,
          attendance_record: { check_in_at: "", check_out_at: "", regularization_note: "Punched by mistake" }
        }
      }.to change(HrLite::AttendanceRecord, :count).by(-1)
      expect(flash[:notice]).to eq("Punch removed.")
    end

    describe "reset today" do
      around { |example| travel_to(Time.current.change(hour: 15)) { example.run } } # both punches on today
      let(:record) do
        create(:attendance_record, user: employee, date: Date.current, work_mode: "wfh", check_in_at: 3.hours.ago,
                                   check_out_at: 1.hour.ago, check_out_lat: 12.9, check_out_lng: 77.6)
      end
      let(:form) do
        { check_in_at: record.check_in_at.strftime("%Y-%m-%dT%H:%M"), check_out_at: record.check_out_at.strftime("%Y-%m-%dT%H:%M"),
          regularization_note: "Checked out by mistake" }
      end

      it "offers both resets on today's fix form" do
        get "/hr/admin/attendances/#{record.user_id}", params: { date: Date.current.to_s }
        expect(response.body).to include(%(value="check_out"), %(value="check_in"))
      end

      it "reset check-out puts them back in, with their work mode" do
        patch "/hr/admin/attendances/#{employee.id}", params: { date: Date.current.to_s, reset: "check_out", attendance_record: form }

        record.reload
        expect([ record.check_in_at, record.check_out_at, record.check_out_lat ]).to match([ be_present, nil, nil ])
        expect(HrLite::WorkModeEvent.open.find_by(user_id: employee.id)).to have_attributes(mode: "wfh", source: "hr")
      end

      it "reset check-in clears the day and lifts its penalties" do
        penalty = HrLite::AttendancePenalty.create!(user_id: employee.id, date: Date.current, minutes: 30, reason: "late",
                                                    attendance_record: record)

        patch "/hr/admin/attendances/#{employee.id}", params: { date: Date.current.to_s, reset: "check_in", attendance_record: form }

        expect(HrLite::AttendanceRecord.exists?(record.id)).to be(false)
        expect(penalty.reload).to have_attributes(removed_by_id: admin.id, removal_reason: "Checked out by mistake")
      end
    end

    it "surfaces validation errors" do
      patch "/hr/admin/attendances/#{employee.id}", params: {
        date: date.to_s,
        attendance_record: { check_in_at: "#{date}T18:00", check_out_at: "#{date}T09:00",
                             regularization_note: "oops" }
      }
      expect(flash[:alert]).to include("must be after check-in")
    end
  end

  describe "punch locations on the day view" do
    before { sign_in admin }

    it "names where each side was punched, how far apart, and counts people per place" do
      create(:office_location, name: "HQ", lat: 28.6315, lng: 77.2167, radius_m: 200)
      create(:attendance_record, :checked_out, user: employee, date: Date.current,
                                 check_in_lat: 28.6315, check_in_lng: 77.2167, check_out_lat: 28.6315, check_out_lng: 77.2373)
      get "/hr/admin/attendances"

      expect(response.body).to include("In: HQ").and include("Out: Off-site · 2.0 km from HQ")
        .and include(%(<span class="hrl-badge hrl-badge--warn">2.0 km apart</span>))
        .and include("Checked in at:</strong>\n        HQ 1").and include("Checked out at:</strong>\n        Off-site 1")
    end
  end

  describe "GET /hr/admin/attendances/week" do
    before { sign_in admin }

    it "totals Mon–Fri hours against a target that drops for leave, and flags anyone below it" do
      HrLite.config.work_hours = { day: 8, probation_day: 9, week: 40 }
      monday = Date.new(2027, 7, 5)
      travel_to(Date.new(2027, 7, 12)) do
        slacker = create(:user, name: "Bina")
        HrLite.config.employees_scope = -> { HrLite.user_klass.where(id: [ employee.id, slacker.id ]) }
        (monday..monday + 4).each do |d|
          start = d.in_time_zone.change(hour: 9)
          create(:attendance_record, user: employee, date: d, check_in_at: start, check_out_at: start + 8.hours) unless d == monday
          create(:attendance_record, user: slacker, date: d, check_in_at: start, check_out_at: start + 7.hours)
        end
        create(:attendance_record, user: slacker, date: monday + 5, check_in_at: monday.in_time_zone + 5.days, check_out_at: monday.in_time_zone + 5.days + 9.hours)
        create(:leave_request, :approved, user: employee, start_date: monday, end_date: monday)

        get "/hr/admin/attendances/week", params: { date: (monday + 2).to_s }
      end

      rows = Nokogiri::HTML(response.body).css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
      expect(rows).to eq([
        [ "Asha", "32.0h", "8.0h", "32.0h", "Met" ],
        [ "Bina", "35.0h", "7.0h", "40.0h", "Below target" ]
      ])
    end
  end

  describe "punch locations on an employee's month" do
    before { sign_in admin }

    it "lists each day's check-in and check-out place with a Google Maps link and the distance" do
      create(:office_location, name: "HQ", lat: 28.6315, lng: 77.2167, radius_m: 200)
      create(:attendance_record, :checked_out, user: employee, date: Date.current,
                                 check_in_lat: 28.6315, check_in_lng: 77.2167, check_out_lat: 28.6315, check_out_lng: 77.2373)
      get "/hr/admin/attendances/#{employee.id}"

      expect(response.body).to include("Where they punched").and include("· HQ").and include("· Off-site · 2.0 km from HQ")
        .and include("https://www.google.com/maps?q=28.6315,77.2373").and include("2.0 km apart")
    end
  end

  describe "GET /hr/admin/attendances/:user_id/summary (one screen per person)" do
    around { |example| travel_to(Time.zone.local(2026, 10, 14, 12)) { example.run } }
    let(:monday) { Date.new(2026, 10, 12) }
    let!(:wfh) do
      HrLite::WfhRequest.new(user_id: employee.id, start_date: monday + 1, end_date: monday + 1, reason: "Plumber", status: "pending")
                        .tap { |r| r.save!(validate: false) }
    end

    before do
      HrLite.config.attendance_slots = true
      record = create(:attendance_record, user: employee, date: monday, check_in_at: Time.zone.local(2026, 10, 12, 9, 30),
                                          check_out_at: Time.zone.local(2026, 10, 12, 18))
      HrLite::AttendancePenalty.create!(user_id: employee.id, date: monday, minutes: 30, reason: "late", attendance_record: record)
      HrLite::Expense.new(user_id: employee.id, category: HrLite::ExpenseCategory.create!(name: "Travel"), amount: 500,
                          spent_on: monday, description: "Cab", status: "submitted").save!(validate: false)
      build(:leave_request, user: employee, leave_type: create(:leave_type, name: "Casual"), start_date: monday + 2, end_date: monday + 2, days_count: 1).save!(validate: false)
      build(:comp_off_request, user: employee, date_worked: monday + 6).save!(validate: false)
      build(:regularization_request, user: employee, date: monday + 1).save!(validate: false)
      HrLite::Document.new(user_id: employee.id, title: "Passport", category: "identity", visibility: "hr").save!(validate: false)
    end

    it "shows the week by default — days, penalties and requests, each linking to where it is decided" do
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::LEADERSHIP) # holds expense.approve
      get "/hr/admin/attendances/#{employee.id}/summary"
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("12 Oct 2026 – 18 Oct 2026", "Mon 12 Oct", "In 09:30 · Out 18:00 · 8h 30m worked", "+30 min",
                              "/hr/admin/wfh_requests/#{wfh.id}", "Claim · Travel", ">This week<",
                              "Casual", "Comp-off", "Attendance fix", "Document · Passport")
      get "/hr/admin/attendances/#{employee.id}/summary", params: { period: "day", date: monday.iso8601 }
      expect(response.body).to include("Monday 12 October 2026")
      expect(response.body).not_to include("Tue 13 Oct")
    end

    it "lists only the request types this viewer may open, and nobody outside their reach" do
      sign_in user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR)
      get "/hr/admin/attendances/#{employee.id}/summary"
      expect(response.body).to include("/hr/admin/wfh_requests/#{wfh.id}")
      expect(CGI.unescapeHTML(response.body)).not_to include("Claim · Travel") # HR holds no expense.approve

      sign_in employee
      get "/hr/admin/attendances/#{admin.id}/summary"
      expect(response).not_to have_http_status(:ok)
    end

    it "lets HR set a shorter day on a repeat here, and marks the days it covers" do
      profile = create(:employee_profile, user: employee)
      hr = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::HR)
      sign_in hr
      get "/hr/admin/attendances/#{employee.id}/summary"
      expect(response.body).to include("Set a shorter day")

      patch "/hr/admin/attendances/#{employee.id}/shorter_day",
            params: { employee_profile: { hours_allowance_minutes: 90, hours_allowance_reason: "Long commute" },
                      repeat: { freq: "WEEKLY", interval: "1", days: %w[MO WE FR], from: monday.iso8601, ends: "after", count: "6" } }
      expect(response).to redirect_to("/hr/admin/attendances/#{employee.id}/summary#shorter-day")
      expect(profile.reload.hours_allowance_repeat).to eq("FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR;DTSTART=2026-10-12;COUNT=6")
      get "/hr/admin/attendances/#{employee.id}/summary"
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("90 min less</strong> · Every week on Mon, Wed, Fri from 12 Oct 2026, 6 times", "Reason: Long commute")
      expect(body.scan("Day 7h 00m").size).to eq(3)

      patch "/hr/admin/attendances/#{hr.id}/shorter_day", params: { employee_profile: { hours_allowance_minutes: 30 } }
      expect(response).to have_http_status(:not_found)
    end

    it "shows a manager the shorter day without the reason or the form, and refuses their change" do
      profile = create(:employee_profile, user: employee, hours_allowance_minutes: 60, hours_allowance_reason: "Long commute")
      manager = user_with_roles(HrLite::Role::EMPLOYEE, HrLite::Role::MANAGER)
      profile.update!(manager_id: manager.id)
      sign_in manager
      get "/hr/admin/attendances/#{employee.id}/summary"
      expect(response.body).to include("60 min less</strong> · Every day")
      expect(response.body).not_to include("Long commute", "Set a shorter day", "Change shorter day")

      patch "/hr/admin/attendances/#{employee.id}/shorter_day", params: { employee_profile: { hours_allowance_minutes: "" } }
      expect(profile.reload.hours_allowance_minutes).to eq(60)
    end
  end
end
